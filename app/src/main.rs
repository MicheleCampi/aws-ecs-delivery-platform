use std::env;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;
use std::time::Duration;

const VERSION: &str = match option_env!("APP_VERSION") {
    Some(v) => v,
    None => "dev",
};

fn handle(mut stream: TcpStream, env_name: &str) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let mut buf = [0u8; 1024];
    let n = stream.read(&mut buf).unwrap_or(0);
    let req = String::from_utf8_lossy(&buf[..n]);
    let path = req.split_whitespace().nth(1).unwrap_or("/");
    let (status, ctype, body) = match path {
        "/healthz" => ("200 OK", "text/plain", "ok".to_string()),
        "/" => (
            "200 OK",
            "application/json",
            format!(
                "{{\"service\":\"delivery-app\",\"env\":\"{}\",\"version\":\"{}\"}}",
                env_name, VERSION
            ),
        ),
        _ => ("404 Not Found", "text/plain", "not found".to_string()),
    };
    let _ = write!(
        stream,
        "HTTP/1.1 {status}\r\nContent-Type: {ctype}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
}

fn healthcheck(port: &str) -> i32 {
    let Ok(mut s) = TcpStream::connect(format!("127.0.0.1:{port}")) else {
        return 1;
    };
    let _ = s.set_read_timeout(Some(Duration::from_secs(2)));
    let _ = s.write_all(b"GET /healthz HTTP/1.1\r\nHost: localhost\r\n\r\n");
    let mut resp = String::new();
    let _ = s.read_to_string(&mut resp);
    let healthy = resp.starts_with("HTTP/1.1 200");
    if healthy { 0 } else { 1 }
}

fn main() {
    let port = env::var("PORT").unwrap_or_else(|_| "8080".into());
    if env::args().nth(1).as_deref() == Some("healthcheck") {
        std::process::exit(healthcheck(&port));
    }
    let env_name = env::var("APP_ENV").unwrap_or_else(|_| "local".into());
    let listener = TcpListener::bind(format!("0.0.0.0:{port}")).expect("bind failed");
    eprintln!("delivery-app {VERSION} env={env_name} listening on :{port}");
    for stream in listener.incoming().flatten() {
        let e = env_name.clone();
        thread::spawn(move || handle(stream, &e));
    }
}

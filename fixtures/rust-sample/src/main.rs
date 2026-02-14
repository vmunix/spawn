fn greet(name: &str) -> String {
    if name.is_empty() {
        "Hello, World!".to_string()
    } else {
        format!("Hello, {name}!")
    }
}

fn main() {
    println!("{}", greet(""));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_greet_default() {
        assert_eq!(greet(""), "Hello, World!");
    }

    #[test]
    fn test_greet_name() {
        assert_eq!(greet("Rust"), "Hello, Rust!");
    }
}

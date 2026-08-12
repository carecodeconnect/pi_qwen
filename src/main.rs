// Placeholder crate. Nothing in the sandbox runs through this binary — inference is
// llama.cpp / ollama via the scripts (see README). The `mistralrs` dependency marks an
// unbuilt experiment: embedding mistral.rs as a library instead of the external
// `mistralrs-server` route documented in docs/07-engines.md.
fn main() {
    println!("Hello, world!");
}

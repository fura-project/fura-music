//! Opt-in research executable. The default invocation is inert.
//! Include the existing private Rust owner without exporting it through FRB or
//! adding an rlib/production caller. No CDP implementation is copied here.

#[cfg(all(target_os = "linux", not(test)))]
#[allow(dead_code)] // NetEase entry points are not callers of this research binary.
mod linux_system_chromium;

#[cfg(all(target_os = "linux", not(test)))]
fn main() {
    linux_system_chromium::kugou_harness::main();
}

#[cfg(any(not(target_os = "linux"), test))]
fn main() {
    println!("KUGOU_GATE result=NOT_RUN");
}

use std::process::ExitCode;

fn main() -> ExitCode {
    match solo_rxjh::verification::run(std::env::args().skip(1).collect()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("[VERIFY] FAIL: {error}");
            ExitCode::FAILURE
        }
    }
}

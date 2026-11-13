use std::process::ExitCode;

use solo_rxjh::{LaunchOptions, run};

fn main() -> ExitCode {
    let options = match LaunchOptions::parse(std::env::args_os().skip(1)) {
        Ok(options) => options,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::FAILURE;
        }
    };
    if options.help {
        println!("SoloRxjh\n\nUsage: solo-rxjh [--assets-dir PATH] [--save-dir PATH] [--help]");
        return ExitCode::SUCCESS;
    }
    match run(options) {
        Ok(bevy::app::AppExit::Success) => ExitCode::SUCCESS,
        Ok(bevy::app::AppExit::Error(code)) => ExitCode::from(code.get()),
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

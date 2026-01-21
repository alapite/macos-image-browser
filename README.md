# macos-image-browser
A native MacOS image-browser written in Swift, created to investigate the capabilities of open-weight models like the GLM and MiniMax series. As I am *not* a Swift/MacOS developer by trade, I make absolutely no guarantees about how well this application works, and provide it solely for illustrative purposes. What you choose to do with the code is entirely up to you.

## Requirements
1. This project assumes you have XCode installed locally on MacOS, preferably Sequoia or later. 
2. The "build.sh" script has only been tested against Bash, and I have no idea how well it works with Zsh (which is currently the default on Macs).

## Building
Just run './build.sh' from within a Bash shell instance, and wait for the build process to complete, then run 'open ImageBrowser.app' (or double-click on the app icon in a Finder window).

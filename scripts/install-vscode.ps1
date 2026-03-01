Get-Content packages/vscode.txt | ForEach-Object {
    code --install-extension $_ --force
}

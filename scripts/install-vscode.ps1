Get-Content packages/vscode.txt | ForEach-Object {
    code --install-extension $_
}
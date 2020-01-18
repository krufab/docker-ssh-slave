if([System.String]::IsNullOrWhiteSpace($env:IMAGE_NAME)) {
    $env:IMAGE_NAME='jenkins4eval/ssh-agent:test-windows'
}

& docker build -f 8\windows\servercore-1809\Dockerfile-windows -t $env:IMAGE_NAME 8\

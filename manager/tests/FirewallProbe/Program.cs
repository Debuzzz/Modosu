using System.Net.Sockets;

// No osu! endpoint, account, authentication, HTTP payload or score is involved.
using var client = new TcpClient();
using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(6));
try
{
    await client.ConnectAsync("api.nuget.org", 443, timeout.Token);
    Console.WriteLine("TCP_CONNECTED");
    return 0;
}
catch (Exception ex) when (ex is SocketException or OperationCanceledException)
{
    Console.WriteLine("TCP_UNAVAILABLE");
    return 3;
}

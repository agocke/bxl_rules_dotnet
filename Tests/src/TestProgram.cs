using System.IO;

namespace Demo;

public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length != 1)
        {
            return 1;
        }

        File.WriteAllText(args[0], "Hello from CSharp integration test");
        return 0;
    }
}

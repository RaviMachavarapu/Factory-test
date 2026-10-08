// Proves: REQ-991
// A stub: nothing in the /next tests runs Dafny.
method Greet(name: string) returns (s: string)
  ensures |s| >= 7
{
  s := "Hello, " + name;
}

// Fails on purpose: the tests expect this file's error, with its line and
// column, in the output and a non-zero exit.
int OnInit()
{
   undeclared_function();
   return INIT_SUCCEEDED;
}

#property strict
#property indicator_chart_window
#property indicator_buffers 1

double line[];

int OnInit()
{
   SetIndexBuffer(0, line);
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
   for(int i = prev_calculated; i < rates_total; i++)
      line[i] = close[i];
   return rates_total;
}

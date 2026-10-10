#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_LINE

double line[];

int OnInit()
{
   SetIndexBuffer(0, line, INDICATOR_DATA);
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
{
   for(int i = prev_calculated; i < rates_total; i++)
      line[i] = price[i];
   return rates_total;
}

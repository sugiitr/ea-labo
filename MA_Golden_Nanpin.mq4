//+------------------------------------------------------------------+
//|  MA_Golden_Nanpin.mq4                                            |
//|  ロジック: MA ゴールデンクロス ロングのみ + ナンピンマーチン + トレイル |
//+------------------------------------------------------------------+
#property copyright "EA-Labo"
#property version   "1.00"
#property strict

//--- 入力パラメータ
extern int    MA_Fast        = 20;       // 短期MA期間
extern int    MA_Slow        = 50;       // 長期MA期間
extern int    MA_Method      = 0;        // MA種別 (0=SMA,1=EMA,2=SMMA,3=LWMA)
extern int    MA_Price       = PRICE_CLOSE;

extern double LotSize        = 0.01;     // 初回ロット
extern double MartingaleMultiplier = 2.0;// マーチンゲール倍率
extern int    MaxNanpinCount = 5;        // 最大ナンピン回数
extern double NanpinDistance = 20.0;     // ナンピン間隔 (pips)

extern double StopLoss       = 0.0;      // SL (pips, 0=なし)
extern double TakeProfit     = 0.0;      // TP (pips, 0=なし)
extern double TrailStart     = 20.0;     // トレイル開始距離 (pips)
extern double TrailStep      = 10.0;     // トレイルステップ (pips)

extern int    Slippage       = 3;
extern int    MagicNumber    = 20240001;

//--- グローバル変数
double PipPoint;  // 5桁ブローカー対応済みpip単位

//+------------------------------------------------------------------+
int OnInit()
{
   // 5桁ブローカー対応: Digits==3 or 5 なら Point*10
   if(Digits == 3 || Digits == 5)
      PipPoint = Point * 10;
   else
      PipPoint = Point;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // シグナル判定（ロングのみ、ショートは常に false）
   bool buySignal  = IsGoldenCross();
   bool sellSignal = false;  // ショート未使用

   // ナンピン判定（既存ポジションがあれば追加エントリー）
   if(CountOpenOrders() > 0)
   {
      CheckNanpin();
   }
   else
   {
      // 新規エントリー
      if(buySignal)
         OpenBuy(LotSize);
   }

   // トレイリングストップ管理
   ManageTrailing();
}

//+------------------------------------------------------------------+
//| ゴールデンクロス判定                                               |
//+------------------------------------------------------------------+
bool IsGoldenCross()
{
   double maFast0 = iMA(NULL, 0, MA_Fast, 0, MA_Method, MA_Price, 0);
   double maFast1 = iMA(NULL, 0, MA_Fast, 0, MA_Method, MA_Price, 1);
   double maSlow0 = iMA(NULL, 0, MA_Slow, 0, MA_Method, MA_Price, 0);
   double maSlow1 = iMA(NULL, 0, MA_Slow, 0, MA_Method, MA_Price, 1);

   // 前足でfast<=slow、今足でfast>slow → ゴールデンクロス
   return (maFast1 <= maSlow1 && maFast0 > maSlow0);
}

//+------------------------------------------------------------------+
//| ナンピン判定・実行                                                 |
//+------------------------------------------------------------------+
void CheckNanpin()
{
   int nanpinCount = CountOpenOrders();
   if(nanpinCount >= MaxNanpinCount + 1) return; // 初回+ナンピン上限

   // 直近の買いポジション平均価格を取得
   double avgPrice = GetAverageOpenPrice();
   if(avgPrice <= 0) return;

   // 現在値が平均価格からナンピン間隔以上下落したらナンピン
   if(Ask <= avgPrice - NanpinDistance * PipPoint)
   {
      double nanpinLot = GetMartingaleLot(nanpinCount);
      OpenBuy(nanpinLot);
   }
}

//+------------------------------------------------------------------+
//| マーチンゲールロット計算                                           |
//+------------------------------------------------------------------+
double GetMartingaleLot(int nanpinCount)
{
   double lot = LotSize;
   for(int i = 0; i < nanpinCount; i++)
      lot *= MartingaleMultiplier;

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   return lot;
}

//+------------------------------------------------------------------+
//| マーチンゲールリセット確認（最終クローズ時刻で判定）               |
//+------------------------------------------------------------------+
bool CheckMartingaleReset()
{
   // 最終クローズ注文を時刻の最大値で探す（SELECT_BY_POSは時系列順不定）
   datetime lastCloseTime = 0;
   int      lastOrderType = -1;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol())                    continue;
      if(OrderMagicNumber() != MagicNumber)            continue;
      if(OrderType() != OP_BUY)                        continue;

      if(OrderCloseTime() > lastCloseTime)
      {
         lastCloseTime = OrderCloseTime();
         lastOrderType = OrderType();
      }
   }

   // 最後のポジションが利益で閉じていればリセット
   if(lastCloseTime > 0)
   {
      for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderSymbol() != Symbol())                    continue;
         if(OrderMagicNumber() != MagicNumber)            continue;
         if(OrderCloseTime() == lastCloseTime)
            return (OrderProfit() > 0);
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 買い注文発注                                                       |
//+------------------------------------------------------------------+
void OpenBuy(double lot)
{
   double sl = (StopLoss  > 0) ? Ask - StopLoss  * PipPoint : 0;
   double tp = (TakeProfit > 0) ? Ask + TakeProfit * PipPoint : 0;

   int ticket = OrderSend(Symbol(), OP_BUY, lot, Ask, Slippage,
                           NormalizeDouble(sl, Digits),
                           NormalizeDouble(tp, Digits),
                           "MA_Golden_Nanpin", MagicNumber, 0, clrBlue);
   if(ticket < 0)
      Print("OrderSend Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| トレイリングストップ管理                                           |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()      != Symbol())              continue;
      if(OrderMagicNumber() != MagicNumber)           continue;
      if(OrderType()        != OP_BUY)                continue;

      double trailStartPrice = OrderOpenPrice() + TrailStart * PipPoint;
      double newSL           = Bid - TrailStep * PipPoint;

      // トレイル開始距離に達した場合のみSL移動
      if(Bid >= trailStartPrice)
      {
         double currentSL = OrderStopLoss();
         if(newSL > currentSL + PipPoint) // 前回SLより改善した場合のみ更新
         {
            bool res = OrderModify(OrderTicket(), OrderOpenPrice(),
                                   NormalizeDouble(newSL, Digits),
                                   OrderTakeProfit(), 0, clrGreen);
            if(!res)
               Print("OrderModify Error: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 現在の買いポジション数を取得                                       |
//+------------------------------------------------------------------+
int CountOpenOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()      != Symbol())              continue;
      if(OrderMagicNumber() != MagicNumber)           continue;
      if(OrderType()        == OP_BUY) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| 保有ポジションの平均取得価格を計算                                 |
//+------------------------------------------------------------------+
double GetAverageOpenPrice()
{
   double totalLots  = 0;
   double totalValue = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()      != Symbol())              continue;
      if(OrderMagicNumber() != MagicNumber)           continue;
      if(OrderType()        != OP_BUY)                continue;

      totalValue += OrderOpenPrice() * OrderLots();
      totalLots  += OrderLots();
   }

   if(totalLots <= 0) return 0;
   return totalValue / totalLots;
}
//+------------------------------------------------------------------+

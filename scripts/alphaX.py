import math
import argparse
def alphaX(reserve0SnapShot, reserve1SnapShot, reserve0Execution, reserve1Execution):
	executionSpot=(reserve0Execution/reserve1Execution)
	snapShotSpot=  (reserve0SnapShot/reserve1SnapShot)
	delta =  (executionSpot/snapShotSpot-1)
	if(delta<0):
		delta=-delta
	partial= reserve0SnapShot*reserve1SnapShot
	numerator =  math.sqrt(partial)*math.sqrt(reserve0SnapShot)*math.sqrt(delta*reserve1SnapShot+reserve1SnapShot)- (reserve0SnapShot*reserve1SnapShot)
	return  (numerator/reserve1SnapShot)*2**64


	
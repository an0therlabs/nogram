#import "NGCurves.h"

const NSTimeInterval NGSendTransitionDuration = 0.3;

static void NGCurvePoints(NGCurve curve, CGFloat *x1, CGFloat *y1, CGFloat *x2, CGFloat *y2) {
    switch (curve) {
        case NGCurveSendVertical:
            *x1 = 0.19919472913616398; *y1 = 0.010644531250000006; *x2 = 0.27920937042459737; *y2 = 0.91025390625;
            break;
        case NGCurveSendHorizontal:
            *x1 = 0.23; *y1 = 1.0; *x2 = 0.32; *y2 = 1.0;
            break;
    }
}

static CGFloat a(CGFloat a1, CGFloat a2) { return 1.0 - 3.0 * a2 + 3.0 * a1; }
static CGFloat b(CGFloat a1, CGFloat a2) { return 3.0 * a2 - 6.0 * a1; }
static CGFloat c(CGFloat a1) { return 3.0 * a1; }
static CGFloat calcBezier(CGFloat t, CGFloat a1, CGFloat a2) { return ((a(a1, a2) * t + b(a1, a2)) * t + c(a1)) * t; }
static CGFloat calcSlope(CGFloat t, CGFloat a1, CGFloat a2) { return 3.0 * a(a1, a2) * t * t + 2.0 * b(a1, a2) * t + c(a1); }

static CGFloat getTForX(CGFloat x, CGFloat x1, CGFloat x2) {
    CGFloat t = x;
    for (int i = 0; i < 4; i++) {
        CGFloat currentSlope = calcSlope(t, x1, x2);
        if (currentSlope == 0.0) return t;
        CGFloat currentX = calcBezier(t, x1, x2) - x;
        t -= currentX / currentSlope;
    }
    return t;
}

CGFloat NGCurveSolve(NGCurve curve, CGFloat x) {
    CGFloat x1, y1, x2, y2;
    NGCurvePoints(curve, &x1, &y1, &x2, &y2);
    CGFloat value = calcBezier(getTForX(x, x1, x2), y1, y2);
    if (value >= 0.997) value = 1.0;
    return value;
}

CAMediaTimingFunction *NGCurveTimingFunction(NGCurve curve) {
    CGFloat x1, y1, x2, y2;
    NGCurvePoints(curve, &x1, &y1, &x2, &y2);
    return [CAMediaTimingFunction functionWithControlPoints:(float)x1 :(float)y1 :(float)x2 :(float)y2];
}

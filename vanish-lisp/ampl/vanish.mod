var x;
var residual = x^4 - 1;
subject to manifold:
    x^2 - 1 = 0;
maximize violation:
    residual^2;

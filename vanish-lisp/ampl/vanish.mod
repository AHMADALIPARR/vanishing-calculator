# VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# See the LICENSE file for the full text.

var x;
var residual = x^4 - 1;
subject to manifold:
    x^2 - 1 = 0;
maximize violation:
    residual^2;

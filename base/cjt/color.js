/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including color.js!");
} else {

    /**
    Color manipulation routines
    @module color
**/

    (function() {

        // http://easyrgb.com/index.php?X=MATH&H=19#text19
        var _hue_2_rgb = function(v1, v2, vH) {
            if (vH < 0) {
                vH += 1;
            }
            if (vH > 1) {
                vH -= 1;
            }
            if ((6 * vH) < 1) {
                return (v1 + (v2 - v1) * 6 * vH);
            }
            if ((2 * vH) < 1) {
                return (v2);
            }
            if ((3 * vH) < 2) {
                return (v1 + (v2 - v1) * ((2 / 3) - vH) * 6);
            }
            return (v1);
        };

        CPANEL.color = {

            // http://easyrgb.com/index.php?X=MATH&H=19#text19
            hsl2rgb: function(h, s, l) {
                var r, g, b, var_1, var_2;
                if (s == 0) { // HSL from 0 to 1
                    r = l * 255; // RGB results from 0 to 255
                    g = l * 255;
                    b = l * 255;
                } else {
                    if (l < 0.5) {
                        var_2 = l * (1 + s);
                    } else {
                        var_2 = (l + s) - (s * l);
                    }
                    var_1 = 2 * l - var_2;

                    r = 255 * _hue_2_rgb(var_1, var_2, h + (1 / 3));
                    g = 255 * _hue_2_rgb(var_1, var_2, h);
                    b = 255 * _hue_2_rgb(var_1, var_2, h - (1 / 3));
                }

                return [r, g, b];
            }
        };

    })();

}

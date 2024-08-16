if (!("to_base64" in String.prototype)) {

    (function() {
        var utf8_to_bytes = function(utf8_string) {
            var utftext = "";
            var fromCharCode = String.fromCharCode;

            var string_length = utf8_string.length;
            for (var n = 0; n < string_length; n++) {
                var c = utf8_string.charCodeAt(n);

                if (c < 128) {
                    utftext += fromCharCode(c);
                } else if ((c > 127) && (c < 2048)) {
                    utftext += fromCharCode((c >> 6) | 192);
                    utftext += fromCharCode((c & 63) | 128);
                } else {
                    utftext += fromCharCode((c >> 12) | 224);
                    utftext += fromCharCode(((c >> 6) & 63) | 128);
                    utftext += fromCharCode((c & 63) | 128);
                }
            }

            return utftext;
        };

        var bytes_to_utf8 = function(bytes_string) {
            var theString = "";
            var i = 0;
            var c = c1 = c2 = 0;
            var fromCharCode = String.fromCharCode;

            while (i < bytes_string.length) {
                c = bytes_string.charCodeAt(i);

                if (c < 128) {
                    theString += fromCharCode(c);
                    i++;
                } else if ((c > 191) && (c < 224)) {
                    c2 = utftext.charCodeAt(i + 1);
                    theString += fromCharCode(((c & 31) << 6) | (c2 & 63));
                    i += 2;
                } else {
                    c2 = bytes_string.charCodeAt(i + 1);
                    c3 = bytes_string.charCodeAt(i + 2);
                    theString += fromCharCode(((c & 15) << 12) | ((c2 & 63) << 6) | (c3 & 63));
                    i += 3;
                }
            }

            return theString;
        };

        String.prototype.to_base64 = function() {
            return btoa(utf8_to_bytes(this));
        };
        String.prototype.from_base64 = function() {
            return bytes_to_utf8(atob(this));
        };
    })();

}

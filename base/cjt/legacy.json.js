// Use of this file is depricated as of 11.28.   This file maintained only for
// legacy cloned themes.


// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including json.js!");
} else if (typeof YAHOO.lang.JSON == "undefined" || !YAHOO.lang.JSON) {
    alert("You must include the YUI JSON library before including json.js!");
} else {

    /**
	The json module contains properties that reference json for our product.
	@module json
*/

    /**
	The json class contains properties that reference json for our product.
	@class json
	@namespace CPANEL
	@extends CPANEL
*/
    var NativeJson = Object.prototype.toString.call(this.JSON) === "[object JSON]" && this.JSON;

    CPANEL.json = {

        // Native or YUI JSON Parser
        fastJsonParse: function(s, reviver) {
            return NativeJson ?
                NativeJson.parse(s, reviver) : YAHOO.lang.JSON.parse(s, reviver);
        }


    }; // end json object
} // end else statement

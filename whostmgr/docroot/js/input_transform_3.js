function transform_inputs() {
    var inputs = document.getElementsByTagName("input");
    for (var i = 0; i < inputs.length; i++) {
        if (inputs[i].type == "text") {
            if (inputs[i].value.match(/^\s*(On|Off)\s*$/i)) {
                var thisval = inputs[i].value;
                var disabled = inputs[i].disabled;
                var tname = inputs[i].name;
                var parentN = inputs[i].parentNode;
                parentN.removeChild(inputs[i]);

                // we used to do this with dom, but ie chokes

                var newhtml = '<label><input type="radio" ' + (disabled ? 'disabled="true" ' : "") + (thisval.match(/off/i) ? 'checked="checked"' : "") + ' name="' + tname + '" value="Off" />' +
                    "Off</label>" +
                    "&nbsp;&nbsp;" +
                    '<label><input type="radio" ' + (disabled ? 'disabled="true" ' : "") + (thisval.match(/on/i) ? 'checked="checked"' : "") + ' name="' + tname + '" value="On" />' +
                    "On</label>";
                parentN.innerHTML = newhtml;
            }
        }
    }
}

YAHOO.util.Event.addListener(window, "load", transform_inputs, this);

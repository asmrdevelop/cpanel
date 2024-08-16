window.rcmail.addEventListener("init", function(evt) {
    var taskbar = document.querySelector("#taskmenu");
    if( !taskbar ) {

        // We are on old themes, which use #taskbar instead of #taskmenu.
        taskbar = document.querySelector("#taskbar");
    }
    var buttonEl = document.querySelector(".button-cpwebmail");
    var location = window.location.href.split("3rdparty")[0];

    if( taskbar && buttonEl ) {
        buttonEl.onclick = null;
        buttonEl.href = location + "webmail/jupiter/index.html?mailclient=none";

        // The button was being added to the middle of the taskbar so this takes it
        // out of the list and appends it to the end
        taskbar.removeChild(buttonEl);
        taskbar.appendChild(buttonEl);

        // button is initially set to display: none in the CSS file in order to
        // prevent the element from "jumping" on the screen when it is removed from
        // the DOM and then appended again
        buttonEl.style = "display: inline-block";

        // we want to wrap the text normally when this is the elastic
        // skin instead of adding a ellipis
        var buttonChildren = buttonEl.getElementsByTagName("span");
        if (buttonChildren[0]) {
            buttonChildren[0].style["white-space"] = "normal";
        }
    }

});

window.rcmail.addEventListener("listupdate", function(evt) {
    var junkFolder  = document.querySelector("#folderlist-content > ul > li.mailbox.junk");
    var purgeButton = document.querySelector("#toolbar-list-menu li a.button-cptrashempty");
    if( junkFolder && purgeButton ) {
        if( junkFolder.classList.contains('selected')) {
            purgeButton.style = "display: inline-block;";
        } else {
            purgeButton.style = "display: none;";
        }
    }
});

function hideTextAreas() {
    document.getElementById("premain1").style.display = "none";
    document.getElementById("premain2").style.display = "none";
    document.getElementById("premainsave").style.display = "none";
    document.getElementById("mainselect").style.display = "inline";

    document.getElementById("prevhost1").style.display = "none";
    document.getElementById("prevhost2").style.display = "none";
    document.getElementById("prevhostsave").style.display = "none";
    document.getElementById("preselect").style.display = "inline";

    document.getElementById("postvhost1").style.display = "none";
    document.getElementById("postvhost2").style.display = "none";
    document.getElementById("postvhostsave").style.display = "none";
    document.getElementById("postselect").style.display = "inline";

}

function showMain() {
    option = document.forms[0].mainsel;
    type = option.options[option.selectedIndex].value;
    if (type == "version") {
        document.getElementById("premain2").style.display = "inline";
        document.getElementById("premainsave").style.display = "inline";
        document.getElementById("premain1").style.display = "none";
    }
    if (type == "all") {
        document.getElementById("premain1").style.display = "inline";
        document.getElementById("premainsave").style.display = "inline";
        document.getElementById("premain2").style.display = "none";
    }
}

function showPre() {
    option = document.forms[0].presel;
    type = option.options[option.selectedIndex].value;
    if (type == "version") {
        document.getElementById("prevhost2").style.display = "inline";
        document.getElementById("prevhostsave").style.display = "inline";
        document.getElementById("prevhost1").style.display = "none";
    }
    if (type == "all") {
        document.getElementById("prevhost1").style.display = "inline";
        document.getElementById("prevhostsave").style.display = "inline";
        document.getElementById("prevhost2").style.display = "none";
    }
}

function showPost() {
    option = document.forms[0].postsel;
    type = option.options[option.selectedIndex].value;
    if (type == "version") {
        document.getElementById("postvhost2").style.display = "inline";
        document.getElementById("postvhostsave").style.display = "inline";
        document.getElementById("postvhost1").style.display = "none";
    }
    if (type == "all") {
        document.getElementById("postvhost1").style.display = "inline";
        document.getElementById("postvhostsave").style.display = "inline";
        document.getElementById("postvhost2").style.display = "none";
    }
}

var photobox;
var photolist = {};

function centerphotobox() {
    if (photobox) {
        photobox.center();
    }
}

function dophotobox(theme) {
    photobox.setImage(photolist[theme]);
    photobox.show();
    centerphotobox();
    setTimeout(centerphotobox, 1000);
    setTimeout(centerphotobox, 2000);
    setTimeout(centerphotobox, 3000);

}

function init_photobox(photos_array) {
    var count = 0;
    for (var p = 0; p < photos_array.length; p++) {
        photolist[photos_array[p].caption] = count++;
    }
    photobox = new YAHOO.widget.PhotoBox("photobox", {
        effect: {
            effect: YAHOO.widget.ContainerEffect.FADE,
            duration: 0.45
        },
        fixedcenter: true,
        constraintoviewport: true,
        underlay: "none",
        close: true,
        visible: false,
        draggable: false,
        modal: true,
        photos: photos_array,
        width: "250px"
    });
    photobox.render();
}

(function(window) {

    "use strict";

    var CPANEL = window.CPANEL,
        document = window.document;

    var _canvas, _context, _img;

    function _init() {
        if (!_context) {
            _canvas = document.createElement("canvas");
            _context = _canvas.getContext("2d");
        }
    }

    /*
     * Determine whether the client (i.e., browser) has the requisite APIs
     * to execute this module's code.
     *
     * @method verify_client_capability
     * @return {Boolean} Whether the client execute this module's code or not.
     */

    function verify_client_capability() {
        try {
            _init();
            return true;
        } catch (e) {
            return false;
        }
    }

    /*
     * Resize an image, and return the result as a data URL.
     * This preserves aspect ratio and centers the resized image.
     *
     * @method get_resized_image_as_data_url
     * @param opts {Object} the options to pass in
     *  image {HTMLImageElement} The image whose content to resize
     *  width {Number} in pixels
     *  height {Number} in pixels
     *  type {String} the MIME type to return the string as
     *  quality {Number} image quality, 0-1 inclusive (only for JPEG; ignored otherwise)
     * @return {String} The data URL of the resized image.
     */

    function get_resized_image_as_data_url(opts) {
        _init();

        var box_width = opts.width;
        var box_height = opts.height;

        var img_width = opts.image.width;
        var img_height = opts.image.height;

        // There are four possibilities (disregarding sameness cases):
        //  1) box is taller, box is wider
        //  2) img is taller, img is wider.
        //  3) img is taller, box is wider
        //  4) box is taller, img is wider
        //
        // 1) If both box dimensions are bigger, then we want the smaller up-scale
        // (i.e., lesser ratio) so the box still completely encloses the image.
        // 2) If both img dimensions are bigger, we want the larger down-scale
        // (i.e., lesser ratio) for the same reason.
        // 3/4) whether we shrink or expand, the scale is still the lesser of the
        // two ratios.
        //
        // ("Sameness cases" work the same way.)
        var scale = Math.min(box_height / img_height, box_width / img_width);

        var target_width = img_width * scale;
        var target_height = img_height * scale;

        // Let's center the image within the box.
        var x_offset = Math.round((box_width - target_width) / 2);
        var y_offset = Math.round((box_height - target_height) / 2);

        _canvas.width = box_width;
        _canvas.height = box_height;

        _context.drawImage(opts.image, x_offset, y_offset, target_width, target_height);

        // NOTE: Would it be worthwhile to check for toDataURLHD?
        return _canvas.toDataURL(opts.type, opts.quality);
    }

    /*
     * Same interface and functionality as get_resized_image_as_data_url,
     * except this takes in a data URL. This must work ASYNCHRONOUSLY
     * because data URLs load asynchronously (in some browsers, anyhow).
     *
     * @method resize_data_url
     * @param opts {Object}
     *  Same as above, except:
     *  image {String} The data URL whose image to resize.
     *  callback {Object|Function} A YUI 2 (-ish) callback object.
     *      If this is a function, it's treated as the success handler,
     *      and errors are ignored. The success handler receives the data URL
     *      for the resized image.
     * @return {undefined}
     */

    function resize_data_url_image(opts) {
        var myopts = Object.create(opts);

        if (!_img) {
            _img = document.createElement("img");
        }

        var callback = opts.callback;
        if (typeof callback === "function") {
            callback = {
                success: callback
            };
        }

        _img.onload = function(e) {
            myopts.image = _img;
            callback.success(get_resized_image_as_data_url(myopts));
        };

        // Make sure we unset any previous failure handler.
        // (The "Object" function seems a reasonable "no-op".)
        _img.onerror = callback.failure || Object;

        _img.src = opts.image;
    }

    CPANEL.image_resizer = {
        verify_client_capability: verify_client_capability,
        get_resized_image_as_data_url: get_resized_image_as_data_url,
        resize_data_url_image: resize_data_url_image
    };

}(window));

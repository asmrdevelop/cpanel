( function(window) {

    "use strict";

    var max_number_divisions = {
        1: 5,
        1.2: 4,
        1.5: 5,
        1.6: 4,
        2: 5,
        2.5: 5,
        3: 3,
        4: 4,
        5: 5,
        6: 3,
        8: 4,
        9: 3
    };

    // Lex sort works out here the same as a numeric sort.
    var max_numbers = Object.keys(max_number_divisions).sort().map(Number);

    // We can’t rely on D3.js to give us “pretty” tick numbers because
    // LOCALE.format_bytes() uses powers of 1,024 rather than powers of 10
    // to format the numbers. (Heh, that is, as long as the number it’s
    // formatting isn’t itself under 1,024!)
    //
    // For example, if we depended on D3.js, we’d get stuff like:
    //
    // [ "0 bytes", "97,66 KB", "195,31 KB", "292,97 KB", "390,63 KB" ]
    //
    // ...rather than the “friendlier”:
    //
    // [ "0 bytes", "100 KB", "200 KB", "300 KB", "400 KB" ]
    //
    // This function, then, “second guesses” format_bytes() in order
    // to arrive at numbers that will look logical visually on the graph
    // when run through format_bytes().
    //
    function get_tick_values_for_format_bytes(highest_datum) {

        var ticks = [0];

        // No such thing as fractional bytes, so just return
        if (highest_datum < 3) {
            ticks.push(1);
            if (highest_datum > 1) {
                ticks.push(2);
            }
        } else {
            var max_tick;

            var binary_power = 0;  // gets incremented right away

            // base_max_number refers to the “reduced” numbers in the
            // max_number_divisions hash above.
            var base_max_number, binary_multiple, decimal_multiple;

            // At this point we know that at least the top tick will
            // need to be a multiple of 1,024. The trick is that, while
            // looping through powers of 1,024, we still need to check powers
            // of 10.
            TICK_LOOP:
            while (!max_tick) {

                // e.g., whatever byte total counts as 1 of the unit that
                // corresponds with the power of 1,024 that we’re on.
                binary_multiple = Math.pow( 1024, binary_power );

                // NOTE: There is only one special case that allows dec === 3.
                // See below.
                for (var dec = 0; dec <= 3; dec++ ) {
                    decimal_multiple = Math.pow( 10, dec );

                    var multiple = binary_multiple * decimal_multiple;
                    for (var m = 0; m < max_numbers.length; m++) {
                        base_max_number = max_numbers[m];

                        var maybe_max_tick = multiple * base_max_number;

                        // The only case where we actually allow 3 as a decimal
                        // power is the number 1,000.
                        if ((dec === 3) && (maybe_max_tick !== 1000)) {
                            continue;
                        }

                        if ( maybe_max_tick >= highest_datum) {
                            max_tick = maybe_max_tick;
                            break TICK_LOOP;
                        }
                    }
                }

                binary_power++;
                if (binary_power > 10) {
                    throw "Excessive power of 1,024: " + binary_power;
                }
            }

            var tick_count = max_number_divisions[base_max_number];

            var base_tick_interval = base_max_number / tick_count;

            // i.e., the number that will display
            var format_bytes_number = max_tick / binary_multiple;

            for (var t = 1; t < tick_count; t++) {
                var new_tick;

                // Normally we can just add new ticks in simple arithmetic
                // intervals, and everything is fine. If we just stopped there,
                // though, we’d get stuff like:
                //
                // [ "0 bytes", "307.2 KB", "614.4 KB", "921.6 KB", "1.2 MB" ]
                //
                // To guard against this, for numbers over 1,000 replace
                // anything that uses a lower unit than the max tick with the
                // equivalent modifier from the previous “level” of multiplier:
                // reduce the power of 1,024 by 1, then take that times 10^2
                // times whichever level of multiplier. The end goal is that
                // we want, e.g., instead of the above, something like:
                //
                // [ "0 bytes", "300 KB", "600 KB", "900 KB", "1.2 MB" ]
                //
                if ((format_bytes_number < 10) && (max_tick > 1000) && ((t * base_tick_interval) < 1)) {
                    new_tick = t * base_tick_interval * 10 * 100 * Math.pow( 1024, binary_power - 1 );
                } else {

                    // The below *would* work but for JavaScript’s lossy algebra:
                    // new_tick = t * (base_max_number / tick_count) * decimal_multiple * binary_multiple;

                    // This gives the same result algebraically, and JavaScript won’t turn it
                    // into e.g., 89.999999999999.
                    new_tick = t * max_tick / tick_count;
                }
                ticks.push(new_tick);
            }

            ticks.push(max_tick);
        }

        return ticks;
    }

    window.Chart_Utilities = {
        get_tick_values_for_format_bytes: get_tick_values_for_format_bytes
    };

}(window) );

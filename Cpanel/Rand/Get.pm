package Cpanel::Rand::Get;

# cpanel - Cpanel/Rand/Get.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::FHUtils::Blocking ();
use Cpanel::FHUtils::Tiny     ();

our $random_source = '/dev/urandom';

#keyed on the characters to be used for entropy
our %entropy_pool;

our $getrandom_syscall_is_usable;
my $last_entropy_pool_owner = $$;

my %TR_CODE_CACHE_NUM_ACCEPTABLE;
my %TR_CODE_CACHE_BAD_CHARS;

my $DEFAULT_LENGTH = 10;

my @DEFAULT_CHARACTERS = (
    0 .. 9,
    'A' .. 'Z',
    'a' .. 'z',
    '_',
);

my $_default_want_chars_string;    # a cache

my $DEFAULT_PRELOAD_16TH = 200;

my $MAX_READ_ATTEMPTS = 50;

my $NUMBER_OF_ASCII_CHARS = 256;

my $_EINTR = 4;

my $_ENOSYS = 38;

my $SYS_GETRANDOM = 318;

my $GRND_NONBLOCK = 0x0001;

my $srand_initialized = '';    # Used by _assemble_random_data_collection_without_random_device()

#Arguments (all optional):
#
#   - byte length of the returned string. Defaults to $DEFAULT_LENGTH above.
#
#   - array ref of characters to use. Defaults to \@DEFAULT_CHARACTERS above.
#
#   - 1/16th the number of bytes to preload into the entropy cache.
#     Because this function is called from all over, we cache any leftover
#     random characters for future use. This value allows control over the
#     size of that preload. Defaults to 200; i.e., pre-cache 3,200 bytes.
#
sub getranddata {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $bytes_of_random_data_wanted, $my_chars_ar, $preloadcount ) = @_;

    use bytes;       #will go away when we leave this context

    #Each process should use its own entropy.
    my $pid = $$;
    if ( $last_entropy_pool_owner != $pid ) {
        %entropy_pool            = ();
        $last_entropy_pool_owner = $pid;
    }

    $preloadcount ||= $DEFAULT_PRELOAD_16TH;

    # We only preload data into the pool if we are reading
    # anyways
    my $bytes_of_data_to_preload_into_entropy_pool = $preloadcount * 16;

    if ($bytes_of_random_data_wanted) {
        if ( $bytes_of_random_data_wanted =~ tr{0-9}{}c ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid number of bytes.', [$bytes_of_random_data_wanted] );
        }
    }
    else {
        $bytes_of_random_data_wanted = $DEFAULT_LENGTH;
    }

    my $number_of_acceptable_characters;
    my $want_chars;
    if ( !$my_chars_ar ) {
        $my_chars_ar = \@DEFAULT_CHARACTERS;
        $want_chars  = ( $_default_want_chars_string ||= join( '', @DEFAULT_CHARACTERS ) );
    }

    # This is a common value that may be tricky to get right.
    if ( !ref $my_chars_ar && $my_chars_ar eq 'binary' ) {
        $number_of_acceptable_characters = $NUMBER_OF_ASCII_CHARS;
        $want_chars                      = '';
    }
    else {
        $number_of_acceptable_characters = scalar @{$my_chars_ar};
        if ( $number_of_acceptable_characters < 1 || $number_of_acceptable_characters > $NUMBER_OF_ASCII_CHARS ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'InvalidParameter', 'The number of desired characters must be at least 1 and at most 256.' );
        }
        $want_chars ||= join( '', @{$my_chars_ar} );
    }
    $entropy_pool{$want_chars} ||= '';
    my $cur_entropy_pool_sr = \$entropy_pool{$want_chars};

    my ( $code_ref_to_remove_chars_above_upper_limit, $code_ref_to_translate_acceptable_chars ) = _generate_random_data_code_refs( $want_chars, $my_chars_ar );

    my ( $dummy, $failed_read_attempts, $rand_chars, $random_data_remaining, $entropy_pool_remaining );

    my $random_data_collected = '';

    my ( $rand_fh, $rand_fh_bitmask );

    my $random_source_is_usable = 1;

    # we need to discard data that will bias the randomness
    while ( length($random_data_collected) < $bytes_of_random_data_wanted ) {

      READ_FROM_RANDOM_SOURCE:
        while (1) {

            $random_data_remaining = $bytes_of_random_data_wanted - length($random_data_collected);

            last READ_FROM_RANDOM_SOURCE if !$random_source_is_usable;

            #If we've got enough in the entropy pool plus the return string,
            #then we don’t need to read any more. This achieves the optimization
            #from preloading.
            last READ_FROM_RANDOM_SOURCE if ( length($$cur_entropy_pool_sr) + length($random_data_collected) ) >= $bytes_of_random_data_wanted;

            $entropy_pool_remaining = $bytes_of_data_to_preload_into_entropy_pool - length($$cur_entropy_pool_sr);

            if ( !defined $getrandom_syscall_is_usable || $getrandom_syscall_is_usable > 0 ) {
                my $rand_count = $entropy_pool_remaining > $random_data_remaining ? $entropy_pool_remaining : $random_data_remaining;

                my $getrandom = _getrandom( $rand_count, \$rand_chars );

                if ( $getrandom == -1 ) {
                    if ( $! == $_EINTR ) {
                        next READ_FROM_RANDOM_SOURCE;
                    }
                    else {

                        # Any other error including ENOSYS or EAGAIN
                        # means we cannot use the random source
                        # and we fallback to /dev/urandom
                        #
                        # See https://lwn.net/Articles/693189/ for
                        # why we do this
                        $getrandom_syscall_is_usable = 0;

                        # The above having been said, the only error we
                        # SHOULD see is ENOSYS; anything else is worth
                        # a warning.
                        if ( $! != $_ENOSYS ) {
                            warn "getrandom() failed: $! - falling back to $random_source";
                        }
                    }
                }
                else {
                    $getrandom_syscall_is_usable = $getrandom ? 1 : 0;
                }
            }

            if ( !$getrandom_syscall_is_usable ) {
                if ( !$rand_fh ) {
                    if ( open $rand_fh, '<:stdio', $random_source ) {
                        $random_source_is_usable = -c $rand_fh ? 1 : 0;
                        if ($random_source_is_usable) {
                            Cpanel::FHUtils::Blocking::set_non_blocking($rand_fh);
                        }
                        else {
                            warn "“$random_source” is unusable because it is not a character device!";
                        }
                    }
                    else {
                        warn "Failed to open($random_source): $!";
                        $random_source_is_usable = 0;
                    }

                    last READ_FROM_RANDOM_SOURCE if !$random_source_is_usable;
                }

                sysread( $rand_fh, $rand_chars, $entropy_pool_remaining > $random_data_remaining ? $entropy_pool_remaining : $random_data_remaining ) or do {
                    if ( ++$failed_read_attempts > $MAX_READ_ATTEMPTS ) {
                        warn "Failed $MAX_READ_ATTEMPTS times to read from “$random_source”! Last failure was: $!";
                        $random_source_is_usable = 0;
                        last READ_FROM_RANDOM_SOURCE;
                    }

                    $rand_fh_bitmask ||= Cpanel::FHUtils::Tiny::to_bitmask($rand_fh);

                    # If we fail to read from $random_source,
                    # then sleep for 12.5 milliseconds OR until the filehandle
                    # is ready for read.

                    #NOTE: failure is ok here.
                    select( $dummy = $rand_fh_bitmask, undef, undef, 0.0125 );

                    next READ_FROM_RANDOM_SOURCE;
                };
            }

            #This is how we ensure (as best we can!) that each character
            #is equally likely to be included in the returned string.
            $code_ref_to_remove_chars_above_upper_limit->( \$rand_chars ) if $code_ref_to_remove_chars_above_upper_limit;

            # Now translate values into acceptable charaters. The coderef
            # we built above will take the random data and convert
            # it to the acceptable characters we provided so they are
            # equally likely to be returned.
            $code_ref_to_translate_acceptable_chars->( \$rand_chars ) if $code_ref_to_translate_acceptable_chars;

            $$cur_entropy_pool_sr .= $rand_chars;
        }

        if ( length $$cur_entropy_pool_sr ) {
            $random_data_collected .= substr( $$cur_entropy_pool_sr, 0, $random_data_remaining, '' );    # just take what we need
        }
        else {
            warn "Using slow randomization logic!";

            # If we get here, the system likely failed to open the $random_source,
            # or the $random_source was not a valid character device.
            $random_data_collected .= _assemble_random_data_collection_without_random_device(
                $number_of_acceptable_characters == $NUMBER_OF_ASCII_CHARS ? [ map { chr } 0 .. 255 ] : $my_chars_ar,

                #We might have already collected some random data.
                $bytes_of_random_data_wanted - length($random_data_collected),
            );
        }
    }

    close($rand_fh) if ref $rand_fh;

    return substr( $random_data_collected, 0, $bytes_of_random_data_wanted );
}

sub _assemble_random_data_collection_without_random_device {
    my ( $my_chars_ar, $bytes_of_random_data_wanted ) = @_;

    # Per srand() documentation, the seed should only be initialized once per process.
    # Otherwise entropy could actually decrease.

    my $process_fingerprint = "$>:$<:$):$$";
    unless ( $srand_initialized eq $process_fingerprint ) {
        $srand_initialized = $process_fingerprint;
        srand();
    }

    my $num_chars = @$my_chars_ar;

    my $random_data_collected = q<>;
    $random_data_collected .= $my_chars_ar->[ rand $num_chars ] for ( 1 .. $bytes_of_random_data_wanted );

    return $random_data_collected;
}

sub clear_pool {
    %entropy_pool = ();
    return;
}

sub _generate_random_data_code_refs {
    my ( $want_chars, $my_chars_ar ) = @_;

    if ( !ref $my_chars_ar ) {

        #binary
        return ();
    }

    my ( $code_ref_to_remove_chars_above_upper_limit, $code_ref_to_translate_acceptable_chars );

    #----------------------------------------------------------------------
    #We need to ensure that each character is equally likely to be chosen.
    #
    #If, for instance, we have $my_chars_ar = [ 0 .. 9 ], that’s a
    #10-character field from which to choose. Our randomizer source will
    #give us a stream of pseudorandom bytes; i.e., 256 possible numbers
    #(0 - 255). We then do:
    #
    #   my $random_char = $my_chars_ar->[ ord($byte) % @$my_chars_ar ]
    #
    #The above, however, would bias the randomness in favor of 0 .. 5.
    #We accommodate for this by ignoring, in this case, byte values
    #250 - 255. This reduces the used random values to 0 - 249 (250 possible
    #values), which makes each character equally likely to be chosen.
    #----------------------------------------------------------------------

    my $number_of_acceptable_characters = scalar @$my_chars_ar;
    my ( $last_good_value_hex, $last_good_value );
    my $first_bad_value = $NUMBER_OF_ASCII_CHARS - ( $NUMBER_OF_ASCII_CHARS % $number_of_acceptable_characters );
    if ( $first_bad_value != $NUMBER_OF_ASCII_CHARS ) {

        # In this we do not have an equal likely set
        # and we need to strip enough characters to
        # ensure equal likelyness of choice
        my $first_bad_value_hex = sprintf( '%02x', $first_bad_value );
        $last_good_value                            = $first_bad_value - 1;
        $last_good_value_hex                        = sprintf( '%02x', $last_good_value );
        $code_ref_to_remove_chars_above_upper_limit = $TR_CODE_CACHE_BAD_CHARS{$first_bad_value_hex} ||= eval 'sub { ${$_[0]} =~ tr/\x' . $first_bad_value_hex . '-\xff//d; }';    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
    }
    else {
        $last_good_value_hex = 'ff';
        $last_good_value     = 255;
    }

    $code_ref_to_translate_acceptable_chars = $TR_CODE_CACHE_NUM_ACCEPTABLE{$want_chars} ||= eval 'sub { ${$_[0]} =~ tr/\x{0}-\x{' . $last_good_value_hex . '}/' . join( '', map { quotemeta( $my_chars_ar->[ $_ % $number_of_acceptable_characters ] ) } ( 0 .. $last_good_value ) ) . '/; }';    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)

    return ( $code_ref_to_remove_chars_above_upper_limit, $code_ref_to_translate_acceptable_chars );

}

sub _getrandom {
    my ( $rand_count, $rand_chars_sr ) = @_;
    return syscall( 0 + $SYS_GETRANDOM, ( $$rand_chars_sr = "\0" x $rand_count ), 0 + $rand_count, 0 + $GRND_NONBLOCK );
}
1;

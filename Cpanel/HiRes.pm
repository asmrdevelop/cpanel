package Cpanel::HiRes;

# cpanel - Cpanel/HiRes.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::HiRes - A module to route calls to cPanel's PurePerl or Time::HiRes's XS function.

=head1 SYNOPSIS

    use Cpanel::HiRes;

    my @res = Cpanel::HiRes::stat($temp_file);
    @res = Cpanel::HiRes::lstat($temp_file);

    Cpanel::HiRes::utime( 6, 6, $temp_file );
    Cpanel::HiRes::lutime( 6, 6, $temp_file );

    open($temp_fh, '<', $temp_file);    # error check omitted for brevity

    @res = Cpanel::HiRes::fstat($temp_fh);
    Cpanel::HiRes::futime( 5, 5, $temp_fh );

To preload one backend or the other:

    use Cpanel::HiRes ( preload => 'xs' );

    # … or:
    use Cpanel::HiRes ( preload => 'perl' );

    # … or the equivalent call to import()

=head1 DESCRIPTION

L<Cpanel::TimeHiRes>, C<Cpanel::NanoStat>, and C<Cpanel::NanoUtime> implement
the same functionality as L<Time::HiRes> but in pure Perl. The pure Perl
modules are lighter, but the XS module is faster.

This module implements “do-the-best-thing” behavior: if the XS module is loaded
then we use that; otherwise we use pure Perl (lazy-loading if needed).

=head1 CAVEATS

=over

=item * To do operations on filehandles you must call C<futime()> and
C<fstat()>.

=item * B<IMPORTANT:> Because the XS implementation doesn’t accept file
descriptors, and because XS is always preferred when it’s available,
you must B<NOT> pass file descriptors to C<futime()> or C<fstat()>.

=item * C<lutime()> has no XS implementation, so the pure Perl version
is always loaded to implement this functionality.

=item * The XS C<utime()> mimics Perl’s in accepting multiple
filenames/filehandles; however, the pure Perl one does not. It’s generally
inadvisable anyway because it makes reliable error reporting impossible, but
if you absolutely must, then you also must preload the XS backend to ensure
that you get that implementation.

=back

=cut

my %_routes = (

    # function => [Cpanel::XXX Pure Perl Module,Pure Perl Function,Time HiRes function (XS), needs closure ],....

    # For some reason Time::HiRes’s stat() and lstat() functions
    # don’t work when assigned directly to a typeglob and need to
    # be wrapped in a closure instead. Neither time() nor utime()
    # has this problem.
    'fstat' => [ 'NanoStat', 'fstat', 'stat',  1 ],
    'lstat' => [ 'NanoStat', 'lstat', 'lstat', 1 ],
    'stat'  => [ 'NanoStat', 'stat',  'stat',  1 ],

    'time' => [ 'TimeHiRes', 'time', 'time' ],

    'utime'  => [ 'NanoUtime', 'utime',  'utime' ],
    'futime' => [ 'NanoUtime', 'futime', 'utime' ],

    # NB: Time::HiRes doesn’t implement lutime().
    'lutime' => [ 'NanoUtime', 'lutime', undef ],
);

my $preloaded;

=head1 FUNCTIONS

This module implements the following functions:

=over

=item * C<time()>

=item * C<stat()>, C<lstat()>, and C<fstat()>

=item * C<utime()>, C<lutime()>, and C<futime()>

=back

The following controls the abstraction:

=head2 I<CLASS>->import( %OPTS )

Thus far %OPTS can be either C<preload =E<gt> 'xs'>
or C<preload =E<gt> 'perl'>.

=cut

sub import {
    my ( $class, %opts ) = @_;

    if ( my $preload = $opts{'preload'} ) {
        if ( $preload eq 'xs' ) {
            require Time::HiRes;
        }
        elsif ( $preload eq 'perl' ) {
            if ( !$preloaded ) {
                require Cpanel::TimeHiRes;    # PPI USE OK - preload
                require Cpanel::NanoStat;     # PPI USE OK - preload
                require Cpanel::NanoUtime;    # PPI USE OK - preload
            }
        }
        else {
            die "Unknown “preload”: “$preload”";
        }

        $preloaded = $preload;
    }

    return;
}

our $AUTOLOAD;

=head2 AUTOLOAD()

See Autoloading in perlsub

=cut

sub AUTOLOAD {    ## no critic qw(Subroutines::RequireArgUnpacking)
    substr( $AUTOLOAD, 0, 1 + rindex( $AUTOLOAD, ':' ) ) = q<>;

    if ( !$AUTOLOAD || !$_routes{$AUTOLOAD} ) {
        die "Unknown function in Cpanel::HiRes::$_[0]";
    }

    my $function = $AUTOLOAD;

    undef $AUTOLOAD;

    my ( $pp_module, $pp_function, $xs_function, $xs_needs_closure ) = @{ $_routes{$function} };

    no strict 'refs';

    # XS
    if ( $INC{'Time/HiRes.pm'} && $xs_function ) {
        *$function = *{"Time::HiRes::$xs_function"};
        return Time::HiRes->can($xs_function)->(@_);
    }
    else {

        # Pure perl
        _require("Cpanel/${pp_module}.pm") if !$INC{"Cpanel/${pp_module}.pm"};

        my $pp_cr = "Cpanel::${pp_module}"->can($pp_function);

        if ($xs_function) {
            *$function = sub {

                # Only use pure Perl as long as Time::HiRes remains unloaded.
                # Once it’s loaded we want to switch to it since it’ll be
                # faster.
                if ( $INC{'Time/HiRes.pm'} ) {
                    *$function = *{"Time::HiRes::$xs_function"};
                    return Time::HiRes->can($xs_function)->(@_);
                }

                goto &$pp_cr;
            };
        }
        else {
            *$function = $pp_cr;
        }
    }

    goto &$function;
}

# for tests
sub _require {
    local ( $!, $^E, $@ );

    require $_[0];
    return;
}

1;

package Cpanel::Template::Plugin::Api2;

# cpanel - Cpanel/Template/Plugin/Api2.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not yet safe her

use base 'Template::Plugin';

use Cpanel::Debug      ();
use Cpanel::Api2::Exec ();

my $_Status;

=head1 MODULE

C<Cpanel::Template::Plugin::Api2>

=head1 DESCRIPTION

C<Cpanel::Template::Plugin::Api2> provides helper methods to call cPanel API2 functions from template toolkit.

=head1 SYNOPSIS

  [%
    USE Api2;
    USE Dumper;

    Api2.pre_exec("Net", "dnszone");
    SET response = Api2.exec("Net", "dnszone", {
        host = RAW_FORM.item('dns')
    });
    Api2.post_exec("Net", "dnszone");

    IF Api2.status().result;
        Dumper.dump(response);
    ELSE;
        Api2.status().reason.html();
    END;
  %]

=head1 CONSTRUTOR

=head2 new

Create a new instance of the plugin.

=cut

sub new {
    my ($class) = @_;
    return bless {
        exec_or_die => \&_api2_exec_or_die,
        exec        => \&_api2_exec,
        pre_exec    => \&_api2_pre_exec,
        post_exec   => \&_api2_post_exec,
    }, $class;
}

=head1 METHODS

=cut

=head2 pre_exec(MODULE, FUNCTION)

Call before you call the C<exec> function to initialize the API2 call environment for one call.

=head3 ARGUMENTS

=over

=item MODULE - string

The module name to load.

=item FUNCTION

The function in the module we want to call.

=back

=head3 RETURNS

N/A

=cut

sub _api2_pre_exec {
    my ( $module, $func ) = @_;

    my $apiref = Cpanel::Api2::Exec::api2_preexec( $module, $func );
    $Cpanel::IxHash::Modify = $apiref->{'modify'} || 'safe_html_encode';
    return;
}

=head2 post_exec(MODULE, FUNCTION)

Call after you call the C<exec> function to tear down the API2 call environment for one call.

=head3 ARGUMENTS

=over

=item MODULE - string

The module name to load.

=item FUNCTION

The function in the module we want to call.

=back

=head3 RETURNS

N/A

=cut

sub _api2_post_exec {
    $Cpanel::IxHash::Modify = 'safe_html_encode';
    return;
}

=head2 exec_or_die(MODULE, FUNCTION, ARGUMENTS)

Call the API and die if there is an error.

=head3 ARGUMENTS

=over

=item MODULE - string

The module name to load.

=item FUNCTION - string

The function in the module we want to call.

=item ARGUMENTS - hash

Each name is the name of the argument and its value is the value of that argument.

=back

=head3 RETURNS

Varies depending on the API you call. It will only be the value in the C<data> field returned in the remote API scenario.

=head3 THROWS

When the API call fails. Possible failures will vary with each API call.

=cut

sub _api2_exec_or_die {
    my ( $module, $func, $params_hr ) = @_;

    my $ret = _api2_exec( $module, $func, $params_hr );
    die "$module\::$func failed!" if !$_Status;

    return $ret;
}

=head2 exec(MODULE, FUNCTION, ARGUMENTS)

Call the API and return the results.

B<NOTE:> This call can overwrite C<$@>.

B<SEE:> C<Api2.status> property to check for success or failure of the API call and the failure reason.

=head3 ARGUMENTS

=over

=item MODULE - string

The module name to load.

=item FUNCTION - string

The function in the module we want to call.

=item ARGUMENTS - hash

Each name is the name of the argument and its value is the value of that argument.

=back

=head3 RETURNS

Varies depending on the API you call. It will only contain the value in the C<data> field returned in the remote API documentation.

=cut

sub _api2_exec {
    my ( $module, $func, $params_hr ) = @_;

    my $apiref = Cpanel::Api2::Exec::api2_preexec( $module, $func );

    if ($apiref) {
        my ( $data, $status );
        require Cpanel::FHTrap;
        my $fhtrap = Cpanel::FHTrap->new();

        eval { ( $data, $status ) = Cpanel::Api2::Exec::api2_exec( $module, $func, $apiref, $params_hr ); };

        if ($@) {
            local $@;    #For a caller that may want to consume $@.
            $fhtrap->close();

            return undef;
        }

        my $raw = $fhtrap->close();

        if ( length $raw ) {
            Cpanel::Debug::log_warn("Software Error: Data leaked from api2 call: $module\:\:$func: [$raw]");
        }

        $_Status = $status;
        return [] if !defined $data || !defined $data->[0];
        return $data;
    }
    else {

        #Cpanel::Api2::Exec does logging
        return;
    }
}

=head1 PROPERTIES

=head2 status

Get the status of the last API call.

=head2 RETURNS

HashRef with the following properties:

=over

=item event - HashRef

With the following properties:

=over

=item result - Boolean

When 1 the API call succeeded. When 0 the API call failed.

=item reason - String - OPTIONAL

The reason of the last API call failed. This only has meaningful information when C<API2.status.result> returns 0.

=back

=back

=cut

sub status { return $_Status }

1;

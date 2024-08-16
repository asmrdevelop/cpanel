package Cpanel::AdminBin::Utils;

# cpanel - Cpanel/AdminBin/Utils.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AdminBin::Serializer ();
use Cpanel::Logger               ();
my $logger;

our $FH;    # for testing

# This is a separate function so that tests can mock it.
# This is for 'full' and 'simple' adminbins
sub get_command_line_arguments {
    my (@passed_args) = @_;

    return ( 1, @passed_args ) if scalar @passed_args > 1;    # has an action

    my $stdin = $FH || \*STDIN;
    my (@args) = ( @passed_args, split( / /, readline($stdin) ) );

    my $uid    = shift @args;
    my $action = shift @args;
    chomp($action)     if $action;
    chomp( $args[-1] ) if @args;

    return ( 1, $uid, $action, @args );
}

# This is for 'full' adminbins only
sub get_extended_arguments_from_stdin {
    my ($method_name) = @_;

    $method_name ||= '';

    my $input;

    my $stdin = $FH || \*STDIN;
    my $check = readline($stdin);
    chomp($check) if $check;

    local $SIG{'__DIE__'} = sub { };
    my $valid = ( $check && $check eq '.' ) && eval { $input = Cpanel::AdminBin::Serializer::SafeLoadFile($stdin); };

    if ( !$valid ) {
        $logger ||= Cpanel::Logger->new();
        my $message = "Error parsing $method_name input";
        if ($@) {
            $message .= " “$@”";
        }
        else {
            $message .= " “magic . not recieved”";
        }
        $logger->warn($message);
        return ( 0, $message );
    }

    return ( 1, $input );
}

1;

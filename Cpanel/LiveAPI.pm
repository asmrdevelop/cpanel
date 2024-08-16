package Cpanel::LiveAPI;

# cpanel - Cpanel/LiveAPI.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#cp_no_verify - no api autodiscovery
use strict;
use warnings;

our $VERSION = 0.3;

use Cpanel::Binary              ();
use Cpanel::JSON                ();
use Cpanel::Socket::UNIX::Micro ();

our $LIVEAPI_DEBUG_LOG;
our $LIVEAPI_DEBUG_LEVEL;

my $AF_UNIX     = 1;
my $SOCK_STREAM = 1;

sub new {
    my $self = {};
    bless $self;

    # Allow for the use of constants in
    if ( defined $LIVEAPI_DEBUG_LOG ) {
        $self->{'_debug_log'} = $LIVEAPI_DEBUG_LOG;
    }
    if ( defined $LIVEAPI_DEBUG_LEVEL ) {
        $self->set_debug($LIVEAPI_DEBUG_LEVEL);
    }

    my $socketfile = $ENV{'CPANEL_CONNECT_SOCKET'} || $ENV{'CPANEL_PHPCONNECT_SOCKET'};

    if ( !$socketfile || !-e $socketfile ) {
        $self->debug_log( 1, "There was a problem connecting back to the cPanel engine [socket file does not exist or env not set]..  Make sure your script ends with .live.pl or .LiveAPI: $!", 1 );
        return;
    }

    socket( $self->{'_cpanelfh'}, $AF_UNIX, $SOCK_STREAM, 0 );
    my $usock = Cpanel::Socket::UNIX::Micro::micro_sockaddr_un($socketfile);
    if ( !$usock ) {
        $self->debug_log( 1, "There was a problem connecting back to the cPanel engine [could not micro_sockaddr_un].  Make sure your script ends with .live.pl or .LiveAPI: $!", 1 );
        return;
    }
    if ( !connect( $self->{'_cpanelfh'}, $usock ) ) {
        $self->debug_log( 1, "There was a problem connecting back to the cPanel engine [could not connect to socket].  Make sure your script ends with .live.pl or .LiveAPI: $!", 1 );
        return;
    }
    if ( !ref $self->{'_cpanelfh'} ) {

        $self->debug_log( 1, "There was a problem connecting back to the cPanel engine [could not build socket].  Make sure your script ends with .live.pl or .LiveAPI: $!", 1 );
        return;
    }

    $self->{'connected'} = 1;

    $self->exec('<cpaneljson enable="1">');    # enable embedded json in the protocol

    return $self;

}

sub set_debug {
    my $self        = shift;
    my $debug_level = shift;

    if ( int $debug_level ) {

        # Open the debug log if it isn't already
        if ( $debug_level > 0 && !ref $self->{'_debug_fh'} ) {

            # Set the debug log - this is the same behavior as the php version
            $self->{'_debug_log'} ||= ( getpwuid($>) )[7] . '/.cpanel/LiveAPI.log.' . rand(99999999);
            open( $self->{'_debug_fh'}, '>>', $self->{'_debug_log'} );
        }
        elsif ( ref( $self->{'_debug_fh'} ) && $debug_level == 0 ) {

            # Close debug_log if debug logging is being disabled
            close( $self->{'_debug_fh'} );
        }
        $self->{'_debug_level'} = $debug_level;
    }
    else {
        syswrite( STDERR, __PACKAGE__ . '::set_debug given non-integer value, disabling debug logging' . "\n" );
        $self->{'_debug_level'} = 0;
    }
    return 1;

}

sub debug_log {
    my $self    = shift;
    my $level   = shift;
    my $log_msg = shift;
    my $stderr  = shift;

    if ( Cpanel::Binary::is_binary() ) {
        return;
    }

    syswrite( STDERR, ( localtime( time() ) . ' ' . $log_msg . "\n" ) ) if $stderr;

    if ( !$self->{'_debug_level'} ) {
        $self->{'_debug_level'} = 0;
    }

    if ( $level > 0 && $level <= $self->{'_debug_level'} ) {
        if ( ref $self->{'_debug_fh'} ) {
            syswrite( $self->{'_debug_fh'}, ( localtime( time() ) . ' ' . $log_msg . "\n" ) );
        }
        else {
            syswrite( STDERR, 'Attempted to execute debugging statement on closed filehandle' . "\n" );
        }
    }
    return 1;

}

sub debug_log_json {
    my $self   = shift;
    my $str    = shift;
    my $parsed = Cpanel::JSON::Load($str);
    my $log_msg;
    if ($parsed) {
        require Data::Dumper;
        $log_msg = Data::Dumper::Dumper($parsed);
    }
    else {
        $log_msg = "Error decoding JSON string";
    }
    $self->debug_log( 1, 'JSON_decode: ' . $log_msg );
    return 1;
}

sub get_debug_log {
    my $self = shift;
    return $self->{'_debug_log'};
}

sub get_debug_level {
    my $self = shift;
    return $self->{'_debug_level'};
}

sub fetch {
    my $self = shift;
    my $var  = shift;

    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};

    return $self->exec( '<cpanel print="' . $var . '">' );
}

sub api1 {
    my $self = shift;
    return $self->_generic_api( 1, @_ );
}

sub api2 {
    my $self = shift;
    return $self->_generic_api( 2, @_ );
}

sub api3 {    #alias for uapi
    my $self = shift;
    return $self->_generic_api( 3, @_ );
}

sub uapi {
    my $self = shift;
    return $self->_generic_api( 'uapi', @_ );
}

sub header {
    my ( $self, $page_title ) = @_;
    $page_title ||= '';

    if ( !exists $self->{'_dom'} ) {
        my $result = $self->uapi( 'Chrome', 'get_dom', { 'page_title' => $page_title } );
        $self->{'_dom'} = $result->{'cpanelresult'}->{'result'}->{'data'};
    }

    if ( !exists $self->{'_dom'}->{'header'} ) {
        return ( 0, 'No header in DOM response' );
    }

    return $self->{'_dom'}->{'header'};
}

sub footer {
    my ( $self, $page_title ) = @_;
    $page_title ||= '';

    if ( !exists $self->{'_dom'} ) {
        my $result = $self->uapi( 'Chrome', 'get_dom', { 'page_title' => $page_title } );
        $self->{'_dom'} = $result->{'cpanelresult'}->{'result'}->{'data'};
    }

    if ( !exists $self->{'_dom'}->{'footer'} ) {
        return ( 0, 'No footer in DOM response' );
    }

    return $self->{'_dom'}->{'footer'};
}

sub _generic_api {
    my $self    = shift;
    my $version = shift;

    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};
    return $self->api( 'exec', $version, @_ );
}

sub cpanelif {
    my $self = shift;
    my $code = shift;
    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};

    return _simple_result( $self->api( 'if', '1', 'if', 'if', $code ) );
}

sub cpanelfeature {
    my $self    = shift;
    my $feature = shift;
    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};

    return _simple_result( $self->api( 'feature', '1', 'feature', 'feature', $feature ) );
}

sub cpanelprint {
    my $self = shift;
    my $var  = shift;

    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};

    return _simple_result( $self->api1( 'print', '', $var ) );
}

sub cpanellangprint {
    my $self = shift;
    my $key  = shift;
    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};

    return _simple_result( $self->api1( 'langprint', '', $key ) );
}

sub exec {
    my $self        = shift;
    my $code        = shift;
    my $skip_return = shift || 0;

    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};

    # SEND CODE
    my $result = '';
    $self->debug_log( 1, '(exec) SEND:' . $code ) if $self->{'_debug_level'};
    syswrite( $self->{'_cpanelfh'}, ( length($code) . "\n" . $code ) );

    # RECV CODE
    my $bytes_read;
    while ( $bytes_read = sysread( $self->{'_cpanelfh'}, $result, 32768, length $result ) ) {
        last if ( index( $result, '</cpanelresult>' ) > -1 );
    }

    $self->debug_log( 1, '(exec) RECV:' . $result ) if $self->{'_debug_level'};
    return                                          if ($skip_return);

    # Parse out return code, build LiveAPI result
    my $json_start_pos = index( $result, "<cpanelresult>{" );
    if ( $json_start_pos != -1 ) {
        $json_start_pos += 14;
        $self->debug_log_json( substr( _trim($result), $json_start_pos, index( $result, "</cpanelresult>" ) - $json_start_pos ) ) if $self->{'_debug_level'};
        my $parsed = Cpanel::JSON::Load( substr( _trim($result), $json_start_pos, index( $result, "</cpanelresult>" ) - $json_start_pos ) );
        if ( index( $result, '<cpanelresult>{"cpanelresult"' ) == -1 && defined $parsed && $parsed ne '' ) {

            # needed for compat-- api2 tags will end up with both due to the internals $json_start_pos = strpos( $result, "<cpanelresult>" ) + 14;
            return { 'cpanelresult' => $parsed };
        }
        else {
            return $parsed;
        }
    }
    elsif ( index( $result, "<cpanelresult></cpanelresult>" ) != -1 ) {

        # This is a hybird api1/api2/api3 response to ensure that
        # the developer using api gets the error field in the position
        # they are looking for
        return { 'cpanelresult' => { 'error' => 'Error cannot be propagated to liveapi, please check the cPanel error_log.', 'result' => { 'errors' => [ 'Error cannot be propagated to liveapi, please check the cPanel error_log.', ] } } };
    }
    elsif ( index( $result, "<cpanelresult>" ) != -1 ) {
        die "Recieved XML response from cpanel socket in json mode: $result";
    }
}

sub api {
    my ( $self, $reqtype, $version, $module, $func, $arg_ref ) = @_;

    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};

    return $self->exec( "<cpanelaction>\n" . Cpanel::JSON::Dump( { "module" => $module, "reqtype" => $reqtype, "func" => $func, "apiversion" => $version, defined $arg_ref ? ( 'args' => $arg_ref ) : () } ) . "\n</cpanelaction>" );
}

#
# Close the connection and destroy the object
#
# This function will close the socket connection to LiveAPI and execute the class destructor.
# @return void
#
sub end {
    my $self = shift;

    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};

    $self->__destruct();
}

sub __destruct {
    my $self = shift;

    return ( 0, 'The Live Socket has closed, unable to continue.' ) if !$self->{'connected'};

    if ( ref( $self->{'_cpanelfh'} ) ) {
        $self->exec( '<cpanelxml shutdown="1" />', 1 );
        while ( !eof( $self->{'_cpanelfh'} ) ) {
            my $buffer;
            read( $self->{'_cpanelfh'}, $buffer, 32768 );
        }
        close( $self->{'_cpanelfh'} );
    }
    close( $self->{'_debug_fh'} ) if ref $self->{'_debug_fh'};

}

sub _simple_result {
    return shift->{'cpanelresult'}->{'data'}->{'result'};
}

sub _trim {
    $_[0] =~ s/^\s+//;
    $_[0] =~ s/\s+$//;
    $_[0];
}

1;

__END__

=head1 NAME

Cpanel::LiveAPI -  cPanel LiveAPI Class

=head1 SYNOPSIS

 use Cpanel::LiveAPI ();

 my $cpliveapi = Cpanel::LiveAPI->new();  # connect to cpanel

 my $live_api_result = $cpliveapi->api2('module', 'func', { 'key1' => 'value1', 'key2' => 'value2', ...} );

=head1 DESCRIPTION

 This module allows for cPanel frontend pages to be developed in Perl using an object for accessing the APIs.
 For the full documentation please see https://go.cpanel.net/liveapi

 You are free to include this module in your program as long as it is for use with cPanel.
 This module is only licensed for use with the version of cPanel it is distributed with.

 The backend xml api is going to change.  If you ignore this message you will find
 that this module will not work in future versions.  This module will be updated
 if the backend xml api changes.  We will make all efforts to provide backwards
 compatibility, but if you do not use this module with any version of cPanel other then
 the one it is distributed with the results could be disasterous.

 That being said this module should insulate you from those changes if you use its api
 instead of the cPanel xml api which it translates to.

 FOR THE AVOIDANCE OF DOUBT: MAKE SURE YOU ONLY USE THIS MODULE WITH THE VERSION OF CPANEL
 THAT IT CAME WITH

 For debugging purposes you can set the following two varibles to enable debug mode:
   - $LIVEAPI_DEBUG_LEVEL - 0 or 1 - enable or disable debugging
   - $LIVEAPI_DEBUG_LOG - path - The path that you would like to log to.

 There are also several functions available for enabling debug mode.

=head2 Cpanel::LiveAPI methods

=over

=item my $cpliveapi = Cpanel::LiveAPI->new()

 Instantiate the LiveAPI Object

 This will create the "Cpanel::LiveAPI" Object, open the communication socket.
 This method will throw an exception if the socket cannot be opened.

=item $cpliveapi->set_debug(E<lt>debug_levelE<gt>)

=over

=item <debug_level>
The debug level that you wish to use.

=back

 Enable debugging mode

 Passing this a non-zero value will enable socket logging.  This will display all
 communication that happens with cpaneld in ~/.cpanel/LiveAPI.log.$randomstring.  This should
 only be used when attempting to debug the transactions that happen over the
 socket.

 This function takes in an integer as a parameter.  This integer is used to indicate
 the logging level that you want to do.  The valid logging level contained within this
 class are:
   - 0 - Disable Logging
   - 1 - Write socket transactions to the log.


=item $cpliveapi->debug_log(E<lt>levelE<gt>, E<lt>log_msgE<gt>, E<lt>stderrE<gt>)

=over

=item <level>
The level of logging you wish for this to appear in.

=item <log_msg>
The message you wish to have logged.

=item <stderr>
If true, the message will be written to STDERR as well.

=back

 Write to the debug log

 Write a message to the debug log at ~/.cpanel/LiveAPI.log.$random or wherever $self->{'_debug_log'} is set to

=item $cpliveapi->debug_log_json(E<lt>levelE<gt>, E<lt>strE<gt>)

=over

=item <level>
The level of logging you wish for this to appear in.

=item <str>
The JSON data to be logged

=back

 Write JSON data to the debug log

 Write a message to the debug log at ~/.cpanel/LiveAPI.log.$random or wherever $self->{'_debug_log'} is set to

=item $debug_log = $cpliveapi->get_debug_log()

Get the filename of the debug log currently in use.

=item $debug_level = $cpliveapi->get_debug_level()

Return the currently set debug level.

=item $value = $cpliveapi->fetch(E<lt>varE<gt>)

=over

=item <var>
The name of the cPvar that you wish to return (f.ex. $CPDATA{'DNS'} )

=back

 Return the value of a cPvar

=item $live_api_result = $cpliveapi->api1(E<lt>moduleE<gt>, E<lt>funcE<gt>, E<lt>argsE<gt>)

=over

=item <module>
The module containing the API1 call you wish to execute.

=item <func>
The API1 method that you wish to execute

=item <args>
An array reference containing the paramaters for the API1 call.

=back

Execute an API1 call

=item $live_api_result = $cpliveapi->api2(E<lt>moduleE<gt>, E<lt>funcE<gt>, E<lt>argsE<gt>)

=over

=item <module>
The module containing the API1 call you wish to execute.

=item <func>
The API1 method that you wish to execute

=item <args>
A hash reference containing the values for the API2 call, these should be key-pair values.

=back

Execute an API2 call

=item $boolean = $cpliveapi->cpanelfeature(E<lt>featureE<gt>)

=over

=item <feature>
The string that has the feature

=back

Check if an account has access to a specific feature.  Returns a boolean value indicating whether the current account has access to the queried feature.

=item $boolean = $cpliveapi->cpanelprint(E<lt>varE<gt>)

=over

=item <var>
The cPvar that you wish to retrieve the value of

=back

Return the value of a cPvar

This function will return the value of a cPvar, this differs from fetch in the fact that this returns
a raw string rather than the standard LiveAPI data structure.

=over

=item For a list of possible variables that can be expanded see the ExpVar Reference Chart at:
https://go.cpanel.net/PluginVars

=back

=item $boolean = $cpliveapi->cpanellangprint(E<lt>keyE<gt>)

=over

=item <key>
The key that you wish to retrieve the value for.

=back

Process a language key for the user's current language
It should be noted that this method of handling localization in cPanel is no longer supported, a modern alternative should be used instead.
Returns a Translated version of the requested phrase or legacy lang key.

=item $live_api_result = $cpliveapi->exec(E<lt>codeE<gt>, [E<lt>skip_returnE<gt>])

=over

=item <code>
The cPanel tag that you wish to execute

=item <skip_return>
(optional) If set to true, this function will not return anything.

=back

Execute a cpanel tag

This method allows for the execution of cPanel tags via LiveAPI.
This is not the preferred method of executing most API calls, one
the other functions in this class should be used if possible.

=item $live_api_result = $cpliveapi->api(E<lt>reqtypeE<gt>, E<lt>versionE<gt>, E<lt>moduleE<gt>, E<lt>funcE<gt>, E<lt>argsE<gt>)

=over

=item <reqtype>
The type of request that you are making, valid values are 'exec', 'feature' or 'if'

=item <version>
The version of the API that you are calling, valid values are either '1' or '2'

=item <module>
The module containing the function that you want to call.

=item <func>
The function that you want to call.

=item <args>
Hash reference for API2, array reference for API1, string for non exec reqtypes

=back

Execute an API call

It is preferred that you use the api1() or api2() functions contained within this class before this one.

=item $cpliveapi->end()

Close the connection and destroy the object

This function will close the socket connection to LiveAPI and execute the class destructor.

=back

=head1 AUTHOR

cPanel, Inc. <copyright@cpanel.net>

bugs, comments, questions to http://tickets.cpanel.net/submit/

=head1 COPYRIGHT

Copyright (c) 1997-2020 cPanel, L.L.C.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

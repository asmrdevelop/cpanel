
# cpanel - Cpanel/Transport/Files/WebDAV.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::WebDAV;

use strict;
use warnings;
use Cpanel::Locale              ();
use Cpanel::Transport::Response ();
use Cpanel::Transport::Files    ();
use HTTP::Status                ();

our @ISA = ('Cpanel::Transport::Files');
my $locale;

# WebDAV does not support these file properties
# so, these are what we return for these instead
my $DEFAULT_FILE_USER  = "";
my $DEFAULT_FILE_GROUP = "";
my $DEFAULT_FILE_PERMS = "";

sub new {
    my ( $class, $OPTS, $CFG ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    Cpanel::Transport::Files::load_module('HTTP::DAV');

    $OPTS->{'dav'} = _server_login($OPTS);

    my $self = bless $OPTS, $class;
    $self->{'config'} = $CFG;

    return $self;
}

sub _missing_parameters {
    my ($param_hashref) = @_;

    my @result = ();
    foreach my $key (qw/host username password/) {
        if ( !defined $param_hashref->{$key} ) {
            push @result, $key;
        }
    }

    my %defaults = (
        'path'    => '',
        'port'    => '80',
        'timeout' => '30',
        'ssl'     => '0',
    );
    foreach my $key ( keys %defaults ) {
        if ( !defined $param_hashref->{$key} ) {
            $param_hashref->{$key} = $defaults{$key};
        }
    }

    return @result;
}

sub _get_valid_parameters {
    return qw/host port username password path timeout ssl/;
}

sub get_path {
    my ($self) = @_;

    # We need to use an absolute path on the remote machine because we
    # cannot be certain that we are in the root directory, since the root
    # directory might not be a valid location.  See case 70513.
    return "/$self->{'path'}";
}

sub _validate_parameters {
    my ($param_hashref) = @_;
    my @result = ();

    foreach my $key (qw/host username password/) {
        if ( !defined $param_hashref->{$key} ) {
            push @result, $key;
        }
    }

    push @result, 'port' unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'port'}, min => 1, max => 65535 );

    if ( defined $param_hashref->{'ssl'} ) {
        unless ( $param_hashref->{'ssl'} == 1 || $param_hashref->{'ssl'} == 0 ) {
            push @result, 'ssl';

        }
    }

    push @result, 'timeout' unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'timeout'}, min => 30, max => 300 );

    return @result;
}

sub _server_login {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ($OPTS) = @_;

    my @missing = _missing_parameters($OPTS);
    if (@missing) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', __PACKAGE__, \@missing ),
            \@missing
        );
    }

    my @invalid = _validate_parameters($OPTS);
    if (@invalid) {
        die Cpanel::Transport::Exception::InvalidParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” the following parameters were invalid: [list_and,_2]', __PACKAGE__, \@invalid ),
            \@invalid
        );
    }

    # This is needed for self signed certs
    $ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;    ## no critic(Variables::RequireLocalizedPunctuationVars) # This needs to be set for the duration of the process

    # For WebDAV, it's possible to have DAV enabled on a sub directory while it's parent path does not have it, so we can't just check / for DAV access
    my $url = build_url( $OPTS->{'host'}, $OPTS->{'port'}, $OPTS->{'ssl'}, $OPTS->{'path'} );

    my $dav = HTTP::DAV->new();

    # Please do not enable debug for this module.
    # The HTTP::DAV module hardcodes this to an unsafe location.
    # See SEC-467 for details
    # $dav->DebugLevel(2);

    $dav->credentials(
        -user => $OPTS->{'username'},
        -pass => $OPTS->{'password'},
        -url  => $url
    );

    $dav->open( -url => $url )
      or die Cpanel::Transport::Exception::Network::Authentication->new(
        \@_, 0,
        $locale->maketext( 'Could not open “[_1]”: [_2]', $url, $dav->message )
      );

    return $dav;
}

sub build_url {
    my ( $host, $port, $ssl, $path ) = @_;
    my $url;
    my $defp;
    if   ($ssl) { $url = 'https://'; $defp = 443; }
    else        { $url = 'http://';  $defp = 80; }
    $url .= $host;
    if   ($port) { $url .= ':' . $port; }
    else         { $url .= ':' . $defp; }
    $url .= '/';
    $url .= $path if defined $path;
    print STDERR "Using WebDAV URL $url\n";
    return $url;
}

sub _put {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my $self = shift;
    my ( $local, $remote ) = @_;

    # Our handle to the WebDAV server
    my $dav = $self->{'dav'};

    if ( $dav->put( -local => $local, -url => $remote ) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $dav->message() );
    }
}

sub _get {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my $self = shift;
    my ( $remote, $local ) = @_;

    # Our handle to the WebDAV server
    my $dav = $self->{'dav'};

    if ( $dav->get( -url => $remote, -to => $local ) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $dav->message() );
    }
}

# This sub is an override for HTTP::DAV::Response::is_success needed due to flawed logic in the original
sub _is_success_override {
    my $self = shift;
    if ( $self->is_multistatus() ) {
        foreach my $code ( @{ $self->codes() } ) {
            return 1 if ( HTTP::Status::is_success($code) );
        }
    }
    else {
        return ( $self->SUPER::is_success() || 0 );
    }
    return 0;
}

sub _ls {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my $self = shift;
    my ($path) = @_;

    # Our handle to the WebDAV server
    my $dav = $self->{'dav'};

    # Do what HTTP::DAV does but flip the logic, as long as we get at least one 200 response, consider it a success
    no warnings 'redefine';
    local *HTTP::DAV::Response::is_success = \&_is_success_override;

    my $res = $dav->propfind( -url => $path, -depth => 1 );
    unless ($res) {
        my $msg = $dav->message();

        if ( $msg =~ m|not found|i ) {
            die Cpanel::Transport::Exception::PathNotFound->new( \@_, 0, $dav->message() );
        }
        else {
            die Cpanel::Transport::Exception->new( \@_, 0, $dav->message() );
        }
    }

    my @ls;
    if ( $res->is_collection ) {
        my @res_list = $res->get_resourcelist()->get_resources();
        @ls = map { $self->_parse_res_props($_) } @res_list;
    }
    else {
        @ls = ( $self->_parse_res_props($res) );
    }

    return Cpanel::Transport::Response::ls->new( \@_, 1, 'Ok', \@ls );
}

sub _mkdir {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my $self = shift;
    my ($path) = @_;

    # Our handle to the WebDAV server
    my $dav = $self->{'dav'};

    # Save the initial path
    my $init_path = $dav->get_workingurl();

    my $root_path = $self->get_path();
    if ( $self->_does_path_exist($root_path) && $path =~ s|^\Q$root_path\E/?|| ) {
        $dav->cwd($root_path)
          or die Cpanel::Transport::Exception->new( \@_, 0, $dav->message );
    }
    elsif ( $path =~ m|^/.*| ) {
        $dav->cwd("/")
          or die Cpanel::Transport::Exception->new( \@_, 0, $dav->message );
        $path =~ s|^/+||;
    }

    #Remove any trailing slashes from the path
    $path =~ s|/+$||;

    my @segments = split( /\//, $path );

    while ( scalar(@segments) ) {

        my $path_seg = shift @segments;

        # Make this path segment on the server
        # But, not if it already exists
        unless ( $self->_does_path_exist($path_seg) ) {
            $dav->mkcol($path_seg)
              or die Cpanel::Transport::Exception->new( \@_, 0, $dav->message() );
        }

        # Hop into this segment to be able to make the next one
        $dav->cwd($path_seg)
          or die Cpanel::Transport::Exception->new( \@_, 0, $dav->message() );

    }

    # Hop back to the original path now that we are done
    $dav->cwd($init_path)
      or die Cpanel::Transport::Exception->new( \@_, 0, $dav->message() );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _chdir {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my $self = shift;
    my ($path) = @_;

    # Our handle to the WebDAV server
    my $dav = $self->{'dav'};

    if ( $dav->cwd($path) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $dav->message() );
    }
}

sub _rmdir {
    my ( $self, $path ) = @_;
    return $self->_delete($path);
}

sub _delete {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my $self = shift;
    my ($path) = @_;

    # Our handle to the WebDAV server
    my $dav = $self->{'dav'};

    $dav->delete($path)
      or die Cpanel::Transport::Exception->new( \@_, 0, $dav->message() );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _pwd {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ($self) = @_;

    # Our handle to the WebDAV server & host
    my $dav  = $self->{'dav'};
    my $host = $self->{'host'};

    # Save the initial path
    my $path = $dav->get_workingurl();

    # Remove the host url from the current path
    $path =~ s|^$host||i;

    return Cpanel::Transport::Response->new( \@_, 1, 'OK', $path );
}

sub _parse_res_props {
    my ( $self, $res ) = @_;

    my $rel_uri  = $res->get_property('rel_uri');
    my %response = (

        # This could be a URI object or a string.  URI objects have a string
        # overload, so just force it into a string and everything will work.
        'filename' => "$rel_uri",
        'user'     => $DEFAULT_FILE_USER,
        'group'    => $DEFAULT_FILE_GROUP,
        'perms'    => $DEFAULT_FILE_PERMS,
        'mtime'    => $res->get_property('getlastmodified')
    );

    if ( $res->is_collection ) {
        $response{'type'} = 'directory';
        $response{'size'} = 0;
    }
    else {
        $response{'type'} = 'file';
        $response{'size'} = $res->get_property('getcontentlength');
    }

    return \%response;
}

sub _does_path_exist {
    my ( $self, $path ) = @_;

    # Our handle to the WebDAV server
    my $dav = $self->{'dav'};

    # Attempt to get minimal properties for the path
    my $res = $dav->propfind( -url => $path, -depth => 0 );

    print STDERR "Found $path\n" if $res;

    # If it was successful, then return true, it does exist
    return 1 if $res;

    # If there is a path not found error, it does not exist
    my $msg = $dav->message();

    if ( $msg =~ m|not found|i ) {

        # It was not found, therefor doesn't exist
        return 0;
    }
    else {

        # Some other error occured
        return 0;
    }
}

1;

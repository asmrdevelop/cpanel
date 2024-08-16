
# cpanel - Cpanel/Transport/Files/FTP.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::FTP;

use strict;
use Cpanel::Locale              ();
use Cpanel::Transport::Response ();
use Cpanel::Transport::Files    ();

our @ISA = ('Cpanel::Transport::Files');
my $locale;

sub new {
    my ( $class, $OPTS, $CFG ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    Cpanel::Transport::Files::load_module('Net::FTP');

    # Prevent a reference loop; see SWAT-165
    # A shallow clone is just fine here
    my $self = {%$OPTS};
    $self->{'ftp_obj'} = _check_host($OPTS);
    $self->{'config'}  = $CFG;

    return bless $self, $class;
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
        'timeout' => '30',
        'port'    => '21',
        'passive' => '0',
    );
    foreach my $key ( keys %defaults ) {
        if ( !defined $param_hashref->{$key} ) {
            $param_hashref->{$key} = $defaults{$key};
        }
    }

    return @result;
}

sub _get_valid_parameters {
    return qw/host username password path timeout port passive/;
}

sub _validate_parameters {
    my ($param_hashref) = @_;
    my @result = ();

    foreach my $key (qw/host username password/) {
        if ( !defined $param_hashref->{$key} || $param_hashref->{$key} eq '' ) {
            push @result, $key;
        }
    }

    my $passive = $param_hashref->{'passive'};
    if ( ( $passive != 0 ) && ( $passive != 1 ) ) {
        push @result, 'passive';
    }

    push @result, 'port'    unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'port'},    min => 1,  max => 65535 );
    push @result, 'timeout' unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'timeout'}, min => 30, max => 300 );

    return @result;
}

sub _sanitize_parameter {
    my ( $param, $value ) = @_;

    # the path parameter must be relative, not absolute
    if ( $param eq 'path' ) {
        $value =~ s{^/+}{};
    }

    # The other parameters do not need to be sanitized
    return $value;
}

sub _check_host {    ## no critic(RequireArgUnpacking) - passing all args for exception
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

    my $pasv = $OPTS->{'passive'} || 0;
    my $ftp  = Net::FTP->new( $OPTS->{'host'}, Passive => $pasv, Debug => 1, Port => $OPTS->{'port'}, Timeout => $OPTS->{'timeout'} )
      or die Cpanel::Transport::Exception::Network::Connection->new(
        \@_, 0,
        $locale->maketext( 'Cannot connect to “[_1]”.', $OPTS->{'host'} )
      );

    $ftp->login( $OPTS->{'username'}, $OPTS->{'password'} )
      or die Cpanel::Transport::Exception::Network::Authentication->new(
        \@_, 0,
        $locale->maketext( 'Cannot connect to “[_1]” using provided credentials.', $OPTS->{'host'} )
      );

    $ftp->binary();
    return $ftp;
}

sub _put {
    my $self = shift;
    my ( $local, $remote ) = @_;

    if ( $self->{'ftp_obj'}->put( $local, $remote ) ) {
        print STDERR "put( $local, $remote ) \n";
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        print STDERR "put( $local, $remote ) FAILED\n";
        print STDERR $self->{'ftp_obj'}->message . "\n";
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'ftp_obj'}->message );
    }
}

sub _get {
    my $self = shift;
    my ( $remote, $local ) = @_;
    if ( $self->{'ftp_obj'}->get( $remote, $local ) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'ftp_obj'}->message );
    }
}

sub _ls {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my $self = shift;
    my ($path) = @_;

    my @ls;
    eval { @ls = $self->{'ftp_obj'}->dir($path); };
    if ($@) {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'ftp_obj'}->message );
    }

    # Net::FTP will return a blank array if a path does not exist.
    # This may be a possible issue if an FTPd does not report '.' & '..' in an empty directory
    if ( !@ls ) {
        die Cpanel::Transport::Exception::PathNotFound->new(
            \@_, 0,
            $locale->maketext( 'The specified path does not exist: [_1]', $path )
        );
    }

    my @response = map { $self->_parse_ls_response($_) } @ls;
    return Cpanel::Transport::Response::ls->new( \@_, 1, 'OK', \@response );
}

sub _mkdir {
    my $self = shift;
    my ($path) = @_;

    if ( $self->{'ftp_obj'}->mkdir( $path, 1 ) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'ftp_obj'}->message );
    }
}

sub _chdir {
    my $self = shift;
    my ($path) = @_;

    if ( $self->{'ftp_obj'}->cwd($path) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'ftp_obj'}->message );
    }
}

sub _rmdir {
    my $self = shift;
    my ($path) = @_;
    if ( $self->{'ftp_obj'}->rmdir( $path, 1 ) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'ftp_obj'}->message );
    }
}

sub _delete {
    my $self = shift;
    my ($path) = @_;
    if ( $self->{'ftp_obj'}->delete($path) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'ftp_obj'}->message );
    }
}

sub _pwd {
    my ($self) = @_;

    if ( my $path = $self->{'ftp_obj'}->pwd() ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK', $path );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'ftp_obj'}->message );
    }
}

1;

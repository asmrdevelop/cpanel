package Cpanel::Transport::Files::SFTP;

# cpanel - Cpanel/Transport/Files/SFTP.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Locale              ();
use Cpanel::SSH::Key            ();
use Cpanel::Transport::Response ();
use Cpanel::Transport::Files    ();
use File::Temp                  ();

our @ISA = ('Cpanel::Transport::Files');
my $locale;

# OPTS should contain session specific information (credentials, usernames, passwords, keys, etc), $CFG should be
# global configuration information.
#
# Required for instantiation:
# $OPTS contains:
#   'host', 'username' then either 'key' or 'password'.
sub new {
    my ( $class, $OPTS, $CFG ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    Cpanel::Transport::Files::load_module('Net::SFTP::Foreign');
    $CFG ||= {};
    $OPTS->{'sftp_obj'} = _check_host( $OPTS, $CFG );

    my $self = bless $OPTS, $class;
    return $self;
}

sub _missing_parameters {
    my ($param_hashref) = @_;

    # attempt to automatically detect the auth type.
    if ( !defined $param_hashref->{'authtype'} ) {
        if ( exists $param_hashref->{'privatekey'} ) {
            $param_hashref->{'authtype'} = 'key';
        }
        elsif ( exists $param_hashref->{'password'} ) {
            $param_hashref->{'authtype'} = 'password';
        }
    }

    my @result = ();
    foreach my $key (qw/host username authtype/) {
        if ( !defined $param_hashref->{$key} ) {
            push @result, $key;
        }
    }

    my %defaults = (
        'path'    => '',
        'timeout' => '30',
        'port'    => '22',
    );
    foreach my $key ( keys %defaults ) {
        if ( !defined $param_hashref->{$key} ) {
            $param_hashref->{$key} = $defaults{$key};
        }
    }

    # Some additional logic based on the authtype
    my $authtype = $param_hashref->{'authtype'} || 'none';
    if ( $authtype eq 'key' ) {
        if ( !defined $param_hashref->{'privatekey'} ) {
            push @result, 'privatekey';
        }
    }
    elsif ( $authtype eq 'password' ) {
        if ( !defined $param_hashref->{'password'} ) {
            push @result, 'password';
        }
    }

    return @result;
}

sub _get_valid_parameters {
    return qw/host username authtype path timeout port privatekey passphrase password/;
}

sub _validate_parameters {
    my ($param_hashref) = @_;
    my @result = ();

    foreach my $key (qw/host username/) {
        if ( !defined $param_hashref->{$key} || $param_hashref->{$key} eq '' ) {
            push @result, $key;
        }
    }

    my $authtype = $param_hashref->{'authtype'};
    if ( $authtype eq 'key' ) {
        if ( !defined $param_hashref->{'privatekey'} ) {
            push @result, 'privatekey';
        }
        else {

            # Make sure the privatekey is an actual file
            my $file = $param_hashref->{'privatekey'};
            unless ( -s $file and -f $file ) {
                push @result, 'privatekey';
            }
        }
        delete $param_hashref->{'password'};
    }
    elsif ( $authtype eq 'password' ) {
        if ( !defined $param_hashref->{'password'} ) {
            push @result, 'password';
        }
        delete $param_hashref->{'privatekey'};
        delete $param_hashref->{'passphrase'};
    }
    else {
        push @result, 'authtype';
    }

    push @result, 'port'    unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'port'},    min => 1,  max => 65535 );
    push @result, 'timeout' unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'timeout'}, min => 30, max => 300 );

    return @result;
}

#
# Translate our parameters into ones which will be used by
# the SFTP library and store them in the config element
#
sub _translate_parameters {
    my ( $OPTS, $CFG ) = @_;

    $CFG->{'host'}    = $OPTS->{'host'};
    $CFG->{'user'}    = $OPTS->{'username'};
    $CFG->{'port'}    = $OPTS->{'port'};
    $CFG->{'timeout'} = $OPTS->{'timeout'};

    if ( defined $OPTS->{'privatekey'} ) {
        $CFG->{'key_path'}   = $OPTS->{'privatekey'};
        $CFG->{'passphrase'} = $OPTS->{'passphrase'} if defined $OPTS->{'passphrase'};
        delete $CFG->{'password'};
    }
    elsif ( defined $OPTS->{'password'} ) {
        $CFG->{'password'} = $OPTS->{'password'};
        delete $CFG->{'key_path'};
        delete $CFG->{'passphrase'};
    }

    $CFG->{'more'} = [ Cpanel::SSH::Key::host_key_checking_legacy() ];

    $OPTS->{'config'} = $CFG;
    return;
}

sub _check_host {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ( $OPTS, $CFG ) = @_;

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

    # Change our parameters into ones which can be used by the Net::SFTP::Foreign module
    _translate_parameters( $OPTS, $CFG );

    # Instantiate the SFTP object using our converted params

    # Sometimes the real errors show up on STDERR, so we need to catch thos as
    # well as module errors from Net::SFTP::Foreign.  However, if sshd has a
    # banner, we'll get data on STDERR, so don't rely on that alone as
    # indicating an error.
    my $raw_out = File::Temp->new();

    my $sftp_obj = Net::SFTP::Foreign->new( %{ $OPTS->{'config'} }, stderr_fh => $raw_out );
    my $result   = $sftp_obj->error ? undef : $sftp_obj->ls;

    seek( $raw_out, 0, 0 );
    my @stderr = (<$raw_out>);
    close($raw_out);

    # Let the error message be a single line so it will be show up in the UI
    my $error_msg;
    foreach my $line (@stderr) {
        chomp($line);
        $error_msg .= "$line ";
    }

    if ( !$result && $error_msg ) {
        die Cpanel::Transport::Exception::Network::Connection->new( \@_, 0, $error_msg );
    }

    if ( $sftp_obj->error ) {
        if ( $sftp_obj->error eq 'Connection to remote server is broken' ) {

            # An invalid key will return error 37 (which is the same as a connection error)
            die Cpanel::Transport::Exception::Network::Authentication->new( \@_, 0, $sftp_obj->error );
        }
        elsif ( int $sftp_obj->error == 37 ) {

            # 37 is SFTP_ERR_CONNECTION_BROKEN
            die Cpanel::Transport::Exception::Network::Connection->new( \@_, 0, $sftp_obj->error );
        }
        elsif ( int $sftp_obj->error == 50 ) {

            # 50 is SFTP_ERR_PASSWORD_AUTHENTICATION_FAILED
            die Cpanel::Transport::Exception::Network::Authentication->new( \@_, 0, $sftp_obj->error );
        }
        die Cpanel::Transport::Exception->new(
            \@_, 0,
            $locale->maketext( 'The Net::SFTP::Foreign object failed to instantiate: [_1]', $sftp_obj->error )
        );
    }
    else {
        return $sftp_obj;
    }
}

sub _build_response {
    my ( $self, $args, $data ) = @_;
    if ( $self->{'sftp_obj'}->error ) {
        die Cpanel::Transport::Exception->new( $args, 0, $self->{'sftp_obj'}->error );
    }
    else {
        return Cpanel::Transport::Response->new( $args, 1, 'OK', $data );
    }
}

sub _put {    ## no critic(RequireArgUnpacking) - passing all args for response
    my $self = shift;
    my ( $local, $remote ) = @_;
    $self->{'sftp_obj'}->put( $local, $remote, best_effort => 1 );
    return $self->_build_response( \@_ );
}

sub _get {    ## no critic(RequireArgUnpacking) - passing all args for response
    my $self = shift;
    my ( $remote, $local ) = @_;
    $self->{'sftp_obj'}->get( $remote, $local, best_effort => 1 );
    return $self->_build_response( \@_ );
}

sub _mkdir {    ## no critic(RequireArgUnpacking) - passing all args for response
    my $self = shift;
    my ($path) = @_;

    $self->{'sftp_obj'}->mkpath($path);

    return $self->_build_response( \@_ );
}

sub _chdir {    ## no critic(RequireArgUnpacking) - passing all args for response
    my $self = shift;
    my ($path) = @_;
    $self->{'sftp_obj'}->setcwd($path);
    return $self->_build_response( \@_ );
}

sub _rmdir {    ## no critic(RequireArgUnpacking) - passing all args for response
    my $self   = shift;
    my ($path) = @_;
    my $res    = $self->{'sftp_obj'}->rremove($path);

    return $self->_build_response( \@_ );
}

sub _delete {    ## no critic(RequireArgUnpacking) - passing all args for response
    my $self   = shift;
    my ($path) = @_;
    my $res    = $self->{'sftp_obj'}->remove($path);

    return $self->_build_response( \@_ );
}

sub _ls {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my $self   = shift;
    my ($path) = @_;
    my $ls     = $self->{'sftp_obj'}->ls($path);

    if ( $self->{'sftp_obj'}->error ) {
        if ( int $self->{'sftp_obj'}->error == 15 ) {
            die Cpanel::Transport::Exception::PathNotFound->new( \@_, 0, $self->{'sftp_obj'}->error );
        }
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'sftp_obj'}->error );
    }

    my @real_ls  = map { $_->{'longname'} } @{$ls};
    my @response = map { $self->_parse_ls_response($_) } @real_ls;

    return Cpanel::Transport::Response::ls->new( \@_, 1, 'OK', \@response );

}

sub _pwd {    ## no critic(RequireArgUnpacking) - passing all args for response"
    my $self = shift;
    my $cwd  = $self->{'sftp_obj'}->cwd;
    return $self->_build_response( \@_, $cwd );
}

1;

package Cpanel::DB::Mysql::Files;

# cpanel - Cpanel/DB/Mysql/Files.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Logger ();
use Moo;

our $VERSION = 0.05;

=head1 Cpanel::DB::Mysql::Files

An object wrapper to files that are used with mysql.

=cut

=over 4

=cut

has 'logger' => ( 'is' => 'ro', 'default' => sub { Cpanel::Logger->new() } );
has 'user' => ( 'is' => 'rw', 'init_arg' => 'user', 'default' => sub { return ( ( getpwuid($>) )[0] ) } );

has 'accesshosts_file' => (
    'is'      => 'rw',
    'default' => '/var/cpanel/mysqlaccesshosts',
);

has 'accesshosts' => (
    'is'      => 'ro',
    'lazy'    => 1,
    'default' => sub {
        my ($self) = @_;
        return $self->_init_access_hosts;
    },
);

sub my_cnf_file {
    my ($self) = @_;
    return ( getpwnam( $self->user ) )[7] . '/.my.cnf';
}

sub _init_access_hosts {
    my ($self) = @_;
    my $filename = $self->accesshosts_file;

    return if !-e $filename or -z $filename;

    my @hosts = ();
    if ( open my $host_h, '<', $filename ) {
        while ( my $line = <$host_h> ) {
            next if !$line;
            $line =~ s/\s//g;
            $line =~ s/\n//g;
            push @hosts, $line;
        }
    }

    return \@hosts;
}

sub _init_my_cnf {
    my ($self) = @_;
    my $filename = $self->my_cnf_file;

    return if !-e $filename or -z $filename or !-r $filename;

    my $dbpass = '';
    my $dbuser = 'root';
    my $dbhost = 'localhost';
    my $dbport = 3306;

    if ( open( my $dbs, '<', $filename ) ) {
        while ( my $line = <$dbs> ) {
            if ( $line =~ m/^user=(\S+)/ ) {
                $dbuser = $1;
                $dbuser =~ s/^\"|\"$//g;
            }
            if ( $line =~ m/^pass(?:word)?=(\S+)/ ) {
                $dbpass = $1;
                $dbpass =~ s/^\"|\"$//g;
            }
            if ( $line =~ m/^host=(\S+)/ ) {
                $dbhost = $1;
                $dbhost =~ s/^\"|\"$//g;
            }
            if ( $line =~ m/^port=(\S+)/ ) {
                $dbport = $1;
                $dbport =~ s/^\"|\"$//g;
            }
        }
        return { 'user' => $dbuser, 'pass' => $dbpass, 'host' => $dbhost, 'port' => $dbport };
    }
}

=item my_cnf

my_cnf takes a key value of user, pass or host and returns that value from the /root/.my.cnf file

=cut

sub my_cnf {
    my ( $self, $key ) = @_;

    $self->{'my_cnf'} = $self->_init_my_cnf;

    return if !defined $self->{'my_cnf'};

    $key = lc $key;
    if ( $key && exists $self->{'my_cnf'}{$key} ) {
        return $self->{'my_cnf'}{$key};
    }
}

#
# Moving the test for the user into a separate function
# so I can override it in the unit test
# (In the unit test, we write a .my.cnf for a temp user,
# we dont' want to over-write the actual root user's .my.cnf.)
#
sub is_user_root {
    my ($user) = @_;

    return ( defined $user and $user eq 'root' ) ? 1 : 0;
}

sub write_my_cnf {
    my ( $self, $args ) = @_;

    $self->logger->panic('Hash ref must be passed') if ref $args ne 'HASH';

    # We are only updating the .my.cnf for the root account
    # We don't want to write the password in clear text for user accounts
    return unless is_user_root( $args->{'user'} );

    my $user = $args->{'user'};
    my $pass = $args->{'pass'};
    my $host = $args->{'host'} || $self->my_cnf('host') || 'localhost';
    my $port = $args->{'port'} || $self->my_cnf('port') || 3306;

    my ( $uid, $gid, $homedir ) = ( getpwnam($user) )[ 2, 3, 7 ];

    return if !defined $homedir;

    my $my_cnf = $homedir . '/.my.cnf';

    if ( open( my $my_h, '>', $my_cnf ) ) {
        chown( $uid, $gid, $my_cnf );
        chmod( oct(600), $my_cnf );
        print {$my_h} '[client]' . "\n";
        print {$my_h} 'user=' . '"' . $user . '"' . "\n";
        print {$my_h} 'password=' . '"' . $pass . '"' . "\n";
        print {$my_h} 'host=' . '"' . $host . '"' . "\n";
        print {$my_h} 'port=' . '"' . $port . '"' . "\n";
    }
}

=item access_hosts

access_hosts returns a list of hosts from the /var/cpanel/mysqlaccesshosts file

=cut

sub access_hosts {
    my ($self) = @_;
    return ( ref $self->accesshosts eq 'ARRAY' )
      ? @{ $self->accesshosts }
      : ();
}

=back

=cut

1;

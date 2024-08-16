package Whostmgr::Mysql;

# cpanel - Whostmgr/Mysql.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

require 5.004;

use strict;
use Carp                             ();
use Cpanel::Config::LoadConfig       ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::MysqlUtils::Connect      ();
use Cpanel::Logger                   ();

my $logger = Cpanel::Logger->new();

sub new {
    shift;
    my $opts = shift;
    my $self = {};
    $self->{'dbh'}        = undef;
    $self->{'hasmysqlso'} = 0;
    my $db                  = $opts->{'db'};
    my $authentication_file = $opts->{'authentication_file'};
    my $user                = $opts->{'user'};
    my $pass                = $opts->{'pass'};
    my $host                = $opts->{'host'} || Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost';

    # Load authentication parameters from file if not fully specified
    if ( ( !$user || !$pass ) && ( $authentication_file && -e $authentication_file ) ) {
        my $authen_ref = _get_authentication_file_hash_ref($authentication_file);
        if ( !$user && $authen_ref->{'user'} ) {
            $user = $authen_ref->{'user'};
        }
        if ( !$pass && $authen_ref->{'pass'} ) {
            $pass = $authen_ref->{'pass'};
        }
    }

    eval { $self->{'dbh'} = Cpanel::MysqlUtils::Connect::get_dbi_handle( 'database' => $db, 'dbserver' => $host, 'dbuser' => $user, 'dbpass' => $pass ); };

    if ($@) {
        my $error = $@;
        print "<br /><b>Error while connecting to MySQL.</b><br />\n";
        Carp::cluck($error);
        $logger->warn($error);
        print "<br />";
        $self->{'failed'} = 1;
    }
    return bless $self, __PACKAGE__;
}

sub has_failed {
    my $self = shift;
    if ( exists $self->{'failed'} ) {
        return $self->{'failed'};
    }
    return;
}

sub sendmysql {
    my $self = shift;
    my $cmd  = shift;
    if ( $self->{'dbh'} ) {
        my $dbh = $self->{'dbh'};

        eval { $dbh->do($cmd) };
        if ($@) {
            $logger->warn($@);
        }
    }
}

sub destroy {
    my $self = shift;
    return if !$self->{'dbh'};
    $self->{'dbh'}->disconnect();
}

sub safesqlstring {
    my $self = shift;
    if ( ref $self eq __PACKAGE__ && ref $self->{'dbh'} eq 'DBI::db' ) {
        my $safe = $self->{'dbh'}->quote( shift() );
        $safe =~ s/^'|'$//g if shift();
        return $safe;
    }
    else {    # so the old style will work
        $self =~ s{([\\'"])}{\\$1}g;
        $self =~ s{(\n)}{\\n}g;
        $self =~ s{(\r)}{\\r}g;
        $self =~ s{(\cz)}{\\Z}g;
        return $self;
    }
}

sub _get_authentication_file_hash_ref {
    my $file = shift;
    return if !-e $file;
    my $hash_ref = Cpanel::Config::LoadConfig::loadConfig($file);
    foreach my $param ( keys %{$hash_ref} ) {
        if ( defined $hash_ref->{$param} ) {
            $hash_ref->{$param} =~ s{ (?: \A \s* ["'] | ["']\s* \z ) }{}xmsg;
        }
    }
    return $hash_ref;
}

1;

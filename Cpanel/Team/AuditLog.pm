package Cpanel::Team::AuditLog;

# cpanel - Cpanel/Team/AuditLog.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Config::LoadCpConf ();
use Cpanel::Exception          ();
use Cpanel::Fcntl              ();
use Cpanel::FileUtils::Open    ();
use Cpanel::JSON               ();
use Cpanel::Team::Config       ();

=encoding utf-8

=head1 NAME

Cpanel::Team::AuditLog - read the API log

=head1 DESCRIPTION

Provides methods to access the API call history of a cPanel or Team Manager user.

=cut

my $READ_MODE = Cpanel::Fcntl::or_flags(qw( O_RDONLY ));
my $log_file  = '/usr/local/cpanel/logs/api_log';

my $regex = qr/
        ^\[(.+?)\].+?                # Fetching timestamp
        ((?:\w+=[^ =]+\s+)+)         # Fetching user,api_version & login_domain if exists
        ({.+)$                       # Fetching JSON api call info.
/x;

=head1 METHODS

=head2 get_api_log -- retrieves all API log entries for the caller.

    RETURNS: Array of log entry hashes, e.g.:
    {
        api_version    => 'uapi',
        called_by      => 'cptest',
        date_timestamp => '2022-08-11 19:17:22 -0500',
        call           => 'Team::list_team',
        origin         => 'UI',
    }

=cut

sub get_api_log {
    my $team_owner = shift;
    my @audit_log;
    if ( !_check_if_api_log_enabled() ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'To access this feature, ask your system administrator to enable the cPanel API Log from WHM Tweak Settings.' );
    }
    my $team_obj  = Cpanel::Team::Config->new($team_owner);
    my %team_list = map { $_ => 1 } ( keys( %{ $team_obj->load()->{users} } ), $team_owner );

    Cpanel::FileUtils::Open::sysopen_with_real_perms( my $log_fh, $log_file, $READ_MODE, 0600 ) or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $log_file, error => $! ] );
    while ( my $line = <$log_fh> ) {
        if ( my ( $timestamp, $key_value_pairs, $json_data ) = $line =~ /$regex/ ) {

            my %tokens       = split /[= ]/, $key_value_pairs;
            my $domain_owner = '';

            # Skip the exceptions when a domain is deleted.
            eval { $domain_owner = exists $tokens{login_domain} ? Cpanel::Team::Config::_get_domain_owner( $tokens{login_domain} ) : $team_owner; };
            next if !( $domain_owner eq $team_owner && exists $team_list{ $tokens{called_by} } );
            my $api_call_info = Cpanel::JSON::Load($json_data);
            my $user_log      = {};
            $user_log->{date_timestamp} = $timestamp;
            $user_log->{api_version}    = $tokens{api_version};
            $user_log->{called_by}      = $tokens{called_by};
            $user_log->{call}           = $api_call_info->{call};
            $user_log->{origin}         = exists $api_call_info->{uri} || exists $api_call_info->{page} ? 'UI' : 'Terminal';
            push @audit_log, $user_log;
        }

    }
    close $log_fh;
    return @audit_log;
}

sub _check_if_api_log_enabled {
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
    return $cpconf->{'enable_api_log'} ? 1 : 0;
}

1;

package Cpanel::Services;

# cpanel - Cpanel/Services.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache ();
use Cpanel::Debug   ();

# forcelive is for scripts in /usr/local/cpanel/scripts
sub restartservice {
    require Cpanel::Services::Restart;
    goto \&Cpanel::Services::Restart::restartservice;
}

# Returns 1 if service is enabled, 0 if disabled, -1 if unknown
sub is_enabled {
    require Cpanel::Services::Enabled;
    goto &Cpanel::Services::Enabled::is_enabled;
}

sub get_running_process_info {
    my (%args) = @_;

    if ( !exists $args{user} || !defined $args{user} || 0 == length $args{user} ) {
        Cpanel::Debug::log_invalid('No user specified');
        return;
    }
    if ( !exists $args{service} || !defined $args{service} || 0 == length $args{service} ) {
        Cpanel::Debug::log_invalid('No service specified');
        return;
    }
    my ( $service, $user ) = @args{qw/service user/};

    my $service_regex;
    if ( exists $args{regex} and 'REGEX' eq ref $args{regex} ) {
        $service_regex = $args{regex};
    }
    else {
        if ( length $args{'regex'} ) {
            eval {
                local $SIG{'__DIE__'} = sub { return };
                $service_regex = qr/$args{'regex'}/i;
            };
        }
        else {
            $service_regex = get_regex_for_service_command_line($service);
        }
    }
    if ( !$service_regex ) {
        Cpanel::Debug::log_info("Invalid service regex specified /$service/. Regex quoted.");
        $service_regex = qr/\b\Q$service\E\b/;
    }

    my $uid      = $user eq 'root'                              ? 0            : ( Cpanel::PwCache::getpwnam_noshadow($user) )[2];
    my $want_pid = $args{'pid'} && kill( 'ZERO', $args{'pid'} ) ? $args{'pid'} : undef;

    return wantarray ? () : {} unless defined $uid;

    require Cpanel::PsParser;
    my $processes_arr = Cpanel::PsParser::fast_parse_ps( 'resolve_uids' => 0, 'want_uid' => $uid, 'exclude_self' => 1, 'exclude_kernel' => 1, ( $want_pid ? ( 'want_pid' => $want_pid ) : () ) );
    my %process_info_for;

    # eval is to avoid recompile if regex
    # Sort matches so parent processes are before children
    my @matches = sort {
        $a->{'pid'} == $b->{'ppid'}   ? -1 :    # a is parent of b
          $a->{'ppid'} == $b->{'pid'} ? 1 :     # a is child of b
          $a->{'pid'} <=> $b->{'pid'}
    } eval 'grep { $_->{command} =~ m{$service_regex}o } @{$processes_arr}';    ## no critic qw(BuiltinFunctions::ProhibitStringyEval) -- compile regex only once
    require Cpanel::Services::Command;
    foreach my $process (@matches) {
        next if Cpanel::Services::Command::should_ignore_this_command( $process->{'command'} );
        $process_info_for{$service} = $process;
        last;
    }

    return wantarray ? %process_info_for : \%process_info_for;
}

# Returns the PS output which contains the specified user and service
sub check_service {
    my %args             = @_;
    my %process_info_for = get_running_process_info(%args);
    my $process_text;
    while ( my ( $service, $process ) = each %process_info_for ) {
        $process_text .= "$service ($process->{'command'}) running as $process->{'user'} with PID $process->{'pid'} (process table check method)\n";
    }
    return $process_text;
}

sub get_regex_for_service_command_line {
    my ($service) = @_;

    require Cpanel::PsParser;
    my $interpreters_regex = Cpanel::PsParser::get_known_interpreters_regex();
    return qr/(?:
                ^(?:(?:\/usr)?\/sbin\/)?\Q$service\Ed?\b   # The service as the start of the command field
                |
                ^(?:\S+\/$interpreters_regex(?:\s-\S*)*\s+)?\/\S+?\/\Q$service\E\b  # The service with a known interpreter, simple interpreter options, and full path in front of it
                |
                ^\S+\/$interpreters_regex(?:\s-\S*)*\s*\Q$service\E\b  # The service with a known interpreter and simple interpreter options in front of it
          )/ix;
}

sub monitor_enabled_services {
    require Cpanel::Services::Installed::State;
    require Cpanel::Chkservd::Manage;
    my $installed_services_state = Cpanel::Services::Installed::State::get_installed_services_state();
    my @unmonitored_enabled_services =
      grep { $_->{'type'} eq 'services' && $_->{'enabled'} && !$_->{'monitored'} } sort { $a->{'name'} cmp $b->{'name'} } @{$installed_services_state};
    my @results;
    foreach my $service (@unmonitored_enabled_services) {
        if ( Cpanel::Chkservd::Manage::enable( $service->{'chkservd_name'} ) ) {
            push @results, { 'service' => $service->{'name'}, 'monitored' => 1 };
        }
        else {
            push @results, { 'service' => $service->{'name'}, 'monitored' => 0 };
        }
    }
    return \@results;
}

sub get_installed_service_info_by_name {

    #Searches for an installed service. If one is found, it instantiates a Cpanel::Services::Installed::Info object
    #with the service info retrieved from get_installed_services_state(). It will return the service info object
    #If no matching service was found, it returns undef instead of a service info object, so if you plan on chaining,
    #do it in a try/catch block.
    require Cpanel::Services::Installed::State;
    require Cpanel::Services::Installed::Info;
    my $service_name             = shift;
    my $service_object           = undef;
    my $installed_services_state = Cpanel::Services::Installed::State::get_installed_services_state();
    if ( defined $service_name ) {
        foreach my $service ( @{$installed_services_state} ) {
            if ( $service->{'name'} eq $service_name ) {
                $service_object = Cpanel::Services::Installed::Info->new($service);
            }
            last if defined $service_object;
        }
    }
    return $service_object;
}

1;

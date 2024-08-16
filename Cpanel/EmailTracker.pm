package Cpanel::EmailTracker;

# cpanel - Cpanel/EmailTracker.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::CpUserGuard     ();
use Cpanel::Config::LoadCpConf      ();
use Cpanel::Config::LoadUserDomains ();
use Cpanel::Logger                  ();

sub build_maxemails_config {
    my $maxemails = shift;
    if ( !defined $maxemails ) {
        my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
        $maxemails = $cpconf->{'maxemailsperhour'};
    }
    $maxemails =
      defined $maxemails
      ? int $maxemails
      : q{};

    if ( open my $maxemail_fh, '>', '/var/cpanel/maxemailsperhour' ) {
        print {$maxemail_fh} $maxemails;
        close $maxemail_fh;
    }
    else {
        Cpanel::Logger::logger(
            {
                'message' => "Unable to update maxemailsperhour: $!",
                'level'   => 'warn',
                'service' => __PACKAGE__,
            }
        );

    }
    my %MAXEMAILS_DOMAIN;
    my %USER_HAS_DOMAIN_WITH_MAX_EMAIL_PER_HOUR;
    if ( scalar keys %MAXEMAILS_DOMAIN ) {
        my $ud_ref = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
        foreach my $domain ( keys %MAXEMAILS_DOMAIN ) {
            my $user = $ud_ref->{$domain};
            $USER_HAS_DOMAIN_WITH_MAX_EMAIL_PER_HOUR{$user} = undef if $user;    #just need the key in there
        }
    }

    foreach my $user ( keys %USER_HAS_DOMAIN_WITH_MAX_EMAIL_PER_HOUR ) {
        my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
        my $cpuser_data  = $cpuser_guard->{'data'};
        foreach my $domain ( @{ $cpuser_data->{'DOMAINS'} }, $cpuser_data->{'DOMAIN'} ) {
            if ( exists $MAXEMAILS_DOMAIN{$domain} ) {
                $cpuser_data->{ 'MAX_EMAIL_PER_HOUR-' . $domain } = $MAXEMAILS_DOMAIN{$domain};
            }
        }
        $cpuser_guard->save();
    }

    return;
}

1;

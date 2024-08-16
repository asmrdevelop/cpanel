package Cpanel::MailTools::DBS;

# cpanel - Cpanel/MailTools/DBS.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::StringFunc::File   ();
use Cpanel::Config::LoadCpConf ();

#For testing
our $_DBS_FILE_DIR = '/etc';

# Do not call this. it's merely syntactic sugar.
{
    no warnings 'once';
    *setup = *_deprecated_setup;
}

sub _deprecated_setup {
    my ( $domain, %FILES ) = @_;

    if ( ( $Cpanel::Debug::level || 0 ) > 4 ) {
        print STDERR "[Cpanel::MailTools::DBS::setup] domain:[$domain] " . join( " ", map { "$_=[$FILES{$_}]" } sort keys %FILES ) . "\n";
    }

    my $modified = setup_mail_routing_for_domains( [ [ $domain, %FILES ] ] );

    return $modified;
}

sub setup_mail_routing_for_domains {
    my ($config_by_domain_ar) = @_;

    my ( %ADD, %REMOVE );
    foreach my $domain_ref (@$config_by_domain_ar) {
        my ( $domain, %FILES ) = @{$domain_ref};
        $FILES{'localdomains'}  //= 1;
        $FILES{'remotedomains'} //= 0;
        $FILES{'secondarymx'}   //= 0;
        if ( delete $FILES{'update_proxy_subdomains'} ) {
            my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
            if ( exists $cpconf_ref->{'proxysubdomains'} && $cpconf_ref->{'proxysubdomains'} ) {
                my @mail_proxy_subdomains = ( 'autoconfig', 'autodiscover' );
                require Cpanel::Proxy;
                if ( $FILES{'localdomains'} ) {
                    Cpanel::Proxy::setup_proxy_subdomains( 'domain' => $domain, 'subdomain' => \@mail_proxy_subdomains );

                }
                else {
                    Cpanel::Proxy::remove_proxy_subdomains( 'domain' => $domain, 'subdomain' => \@mail_proxy_subdomains );

                }
            }
        }
        foreach my $file ( keys %FILES ) {
            next if ( $FILES{$file} == -1 );
            if ( $FILES{$file} ) {
                push @{ $ADD{$file} }, $domain;
            }
            else {
                push @{ $REMOVE{$file} }, $domain;
            }
        }
    }

    my $modified = 0;
    foreach my $file ( keys %ADD ) {
        $modified = 1 if Cpanel::StringFunc::File::addlinefile( "$_DBS_FILE_DIR/$file", $ADD{$file} );
    }

    foreach my $file ( keys %REMOVE ) {
        $modified = 1 if Cpanel::StringFunc::File::remlinefile( "$_DBS_FILE_DIR/$file", $REMOVE{$file}, 'full' );
    }
    return $modified;

}

sub fetch_system_mail_routing_config_by_domain {
    require Cpanel::Config::LoadConfig;
    return {
        'local'     => scalar Cpanel::Config::LoadConfig::loadConfig( '/etc/localdomains',  undef, '' ),
        'remote'    => scalar Cpanel::Config::LoadConfig::loadConfig( '/etc/remotedomains', undef, '' ),
        'secondary' => scalar Cpanel::Config::LoadConfig::loadConfig( '/etc/secondarymx',   undef, '' ),
    };
}

1;

__END__

=head1 NAME

Cpanel::MailTools::DBS

=head1 SYNOPSIS

    use Cpanel::MailTools::DBS ();
    Cpanel::MailTools::DBS::setup_mail_routing_for_domains([
      [ $domain => ( localdomains => 1, remotedomains => 1 ), ( update_proxy_subdomains => 1 ) ]
    ]);

=head2 FUNCTIONS

=over 4

=item setup_mail_routing_for_domains([ [$DOMAIN => @FILES, @OPTIONS], ... ])

Setup one or more domains. Includes one or more B<DOMAIN_CONFIG> where each
B<DOMAIN_CONFIG> is C<[$DOMAIN, @FILES, @OPTIONS]>. Each B<DOMAIN_CONFIG>
includes B<FILES> with a boolean representing whether or not the file is to be
updated. Valid B<FILES> includes

=over 8

=item localdomains

=item remotedomains

=item secondarymx

=back

Valid B<@OPTIONS> include only C<update_proxy_subdomains> to set configure proxies.

=back


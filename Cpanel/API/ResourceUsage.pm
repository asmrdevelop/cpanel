package Cpanel::API::ResourceUsage;

# cpanel - Cpanel/API/ResourceUsage.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::API::ResourceUsage

=head1 SYNOPSIS

    my $result = Cpanel::API::execute_or_die('ResourceUsage', 'get_usages');

=head1 DESCRIPTION

This module is a successor to the C<StatsBar> module and intends, rather than
specifically addressing a UI component (i.e., the cPanel main page’s stats
bar), to supply a display-agnostic report that the UI logic will massage as
needed for display.

=cut

use strict;
use warnings;

use Cpanel                             ();
use Cpanel::DynamicUI::App             ();
use Cpanel::GlobalCache                ();
use Cpanel::LinkedNode::Worker::GetAll ();
use Cpanel::LoadModule                 ();
use Cpanel::LoadModule::Custom         ();
use Cpanel::LocaleString               ();
use Cpanel::Quota                      ();
use Cpanel::Services::Enabled          ();
use Cpanel::StatsBar                   ();
use Cpanel::Themes                     ();
use Cpanel::Themes::Utils              ();
use Cpanel::Autodie                    ();

use Try::Tiny;

my %FEATURE_ALIAS = (
    'forwarders' => ['emaildomainfwd'],
);

my $available_apps_hr;

#called from test
sub _has_cloudlinux {
    return Cpanel::GlobalCache::data( 'cpanel', 'has_cloudlinux' );
}

#called from test
sub _has_postgres {
    return Cpanel::GlobalCache::data( 'cpanel', 'has_postgres' );
}

sub _ftp_is_enabled {
    return Cpanel::Services::Enabled::is_enabled('ftp');
}

sub _include_mailing_lists {
    return !$Cpanel::CONF{'skipmailman'};
}

sub _cpconf_wants_inode_usage__and_disk_usage_is_available {
    return $Cpanel::CONF{'file_usage'} && Cpanel::Quota::is_available();
}

sub _cpconf_wants_sql_disk_usage {
    return $Cpanel::CONF{'disk_usage_include_sqldbs'};
}

sub _has_postgres_and_cpconf_wants_sql_disk_usage {
    return _cpconf_wants_sql_disk_usage() && _has_postgres();
}

#Order here determines return order,
#which in turn determines UI display order.
#NB: This could be a constant.pm list. The bless()ed objects don’t have
#DESTROY handlers, so it would be safe, but if those objects ever gained
#DESTROY handlers it could create problems that are hard to find.
sub _STATS_METADATA {
    my $acct_is_distributed = !!@{ [ Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser( \%Cpanel::CPDATA ) ] };

    return (
        {
            key     => 'diskusage',
            feature => 'diskusageviewer',
            only_if => \&Cpanel::Quota::is_available,
            id      => 'disk_usage',
            role    => 'FileStorage',
        },
        {
            key         => 'filesusage',
            only_if     => \&_cpconf_wants_inode_usage__and_disk_usage_is_available,
            description => $acct_is_distributed ? Cpanel::LocaleString->new('Local File Usage') : Cpanel::LocaleString->new('File Usage'),
            role        => 'FileStorage',
        },
        {
            key         => 'cachedmysqldiskusage',
            only_if     => \&_cpconf_wants_sql_disk_usage,
            description => Cpanel::LocaleString->new('Database Disk Usage'),
            role        => 'MySQLClient',
        },
        {
            key         => 'cachedpostgresdiskusage',
            only_if     => \&_has_postgres_and_cpconf_wants_sql_disk_usage,
            description => Cpanel::LocaleString->new('PostgreSQL Disk Usage'),
            role        => 'PostgresClient',
        },
        {
            key     => 'bandwidthusage',
            feature => 'bandwidth',
            id      => 'bandwidth',
        },
        {
            key         => 'addondomains',
            feature     => 'addondomains',
            id          => 'addon_domains',
            description => Cpanel::LocaleString->new('Addon Domains'),
            url         => _user_theme_has_addons_ui() ? 'addon/index.html' : 'domains/index.html',
            role        => 'WebServer'
        },
        {
            key         => 'subdomains',
            feature     => 'subdomains',
            role        => 'WebServer',
            description => Cpanel::LocaleString->new('Subdomains'),
            url         => _user_theme_has_subdomains_ui() ? 'subdomain/index.html' : 'domains/index.html',
        },
        {
            key         => 'parkeddomains',
            feature     => 'parkeddomains',
            id          => 'aliases',
            role        => { match => 'any', roles => [qw(WebServer MailReceive)] },
            description => Cpanel::LocaleString->new('Alias Domains'),
            url         => 'domains/index.html'
        },
        {
            key     => 'emailaccounts',
            feature => 'popaccts',
            id      => 'email_accounts',
            role    => { match => 'all', roles => [qw(MailReceive MailSend)] },
        },
        {
            key     => 'mailinglists',
            only_if => \&_include_mailing_lists,
            feature => 'lists',
            id      => 'mailing_lists',
            role    => { match => 'all', roles => [qw(MailReceive MailSend)] },
        },
        {
            key     => 'autoresponders',
            feature => 'autoresponders',
            role    => { match => 'all', roles => [qw(MailReceive MailSend)] },
        },
        {
            key     => 'emailforwarders',
            feature => 'forwarders',
            id      => 'forwarders',
            role    => { match => 'all', roles => [qw(MailReceive MailSend)] },
        },
        {
            key     => 'emailfilters',
            feature => 'blockers',
            id      => 'email_filters',
            role    => 'MailReceive'
        },
        {
            key     => 'ftpaccounts',
            only_if => \&_ftp_is_enabled,
            feature => 'ftpaccts',
            id      => 'ftp_accounts',
            role    => 'FTP'
        },
        {
            key         => 'mysqldatabases',
            feature     => 'mysql',
            id          => 'mysql_databases',
            description => Cpanel::LocaleString->new('Databases'),
            url         => 'sql/index.html',
            role        => 'MySQLClient',
        },
        {
            key     => 'postgresqldatabases',
            only_if => \&_has_postgres,
            feature => 'postgres',
            id      => 'postgresql_databases',
            role    => 'PostgresClient',
        },
    );
}

# Absent from Jupiter, present in Paper Lantern
#
sub _user_theme_has_subdomains_ui () {
    my $theme_name = Cpanel::Themes::get_user_theme($Cpanel::user);
    my $theme_root = Cpanel::Themes::Utils::get_cpanel_theme_root($theme_name);

    return Cpanel::Autodie::exists("$theme_root/subdomain/doaddondomain.html.tt");
}

# Absent from Jupiter, present in Paper Lantern
#
sub _user_theme_has_addons_ui () {
    my $theme_name = Cpanel::Themes::get_user_theme($Cpanel::user);
    my $theme_root = Cpanel::Themes::Utils::get_cpanel_theme_root($theme_name);

    return Cpanel::Autodie::exists("$theme_root/addon/doaddondomain.html.tt");
}

=head1 FUNCTIONS

=head2 get_usages()

Returns a list of hashes. Each hash contains:

=over

=item * C<description> - A text string suitable for display in a UI.

=item * C<id> - A text string, suitable for reference as, e.g., a hash key.

=item * C<maximum> - undef (no limit) or a nonnegative integer.

=item * C<formatter> - An arbitrary string. cPanel’s Paper Lantern UI
recognizes two special values:

=over

=item * C<format_bytes> - To go through the locale system’s formatter
for byte amounts.

=item * C<format_bytes_per_second> - Same as C<format_bytes>, but formats
for a per-second display.

=item * C<percent> - Display B<only> the percentage, not C<usage> nor
C<maximum>.

=back

Third-party API callers may implement logic to recognize and handle whatever
formats they choose.

=item * C<url> - A text string, or undef.

=item * C<usage> - A nonnegative integer.

=back

=cut

#not wrap the #old logic.
sub get_usages {
    my ( $args, $result ) = @_;

    my @result_data;
    Cpanel::StatsBar::_load_stats_ref('bytes');

  STAT:
    for my $schema_item ( _STATS_METADATA() ) {
        next if $schema_item->{'role'}    && !_has_role( $schema_item->{'role'} );
        next if $schema_item->{'only_if'} && !$schema_item->{'only_if'}->();

        my ( $feature, $key, $value, $descr, $url ) = @{$schema_item}{qw( feature key id description url )};

        if ($feature) {
            foreach my $feature_to_check ( $feature, @{ $FEATURE_ALIAS{$feature} || [] } ) {
                next STAT if !Cpanel::hasfeature($feature_to_check);
            }
        }

        $descr = $descr->to_string() if $descr;
        push @result_data, _parse_usage_stat(
            {
                'id'          => $value,
                'description' => $descr,
                'url'         => $url
            },
            $key
        );
    }

    _add_custom_usage_stats( \@result_data );

    for my $rd (@result_data) {
        $rd->{$_} //= undef for ( 'url', 'formatter', 'maximum', 'error' );
    }

    $result->data( \@result_data );

    return 1;
}

sub _parse_usage_stat {
    my ( $stat, $key ) = @_;

    my $rSTATS     = $Cpanel::StatsBar::rSTATS;
    my $cur_rSTATS = $rSTATS->{$key} or die "No “$key”!";

    my ( $max, $usage );

    try {
        if ( $cur_rSTATS->{'module'} ) {
            Cpanel::LoadModule::load_perl_module("Cpanel::$cur_rSTATS->{'module'}");
        }

        ( $max, $usage ) = map { $cur_rSTATS->{$_} } qw( _max _count );
        ( 'CODE' eq ref ) && ( $_ = $_->() ) for ( $max, $usage );
    }
    catch {
        chomp $_;
        $stat->{'error'} = $_;

        ( 'CODE' eq ref ) && ( $_ = undef ) for ( $max, $usage );
    };

    if ( defined $max ) {
        if ( $max eq 'unlimited' || ( $cur_rSTATS->{'zeroisunlimited'} && $max == 0 ) ) {
            $max = undef;
        }
    }

    my $unit = $cur_rSTATS->{'units'};
    $stat->{'formatter'} = !$unit ? undef : do {

        #“MB” is legacy for Cpanel::StatsBar.
        if ( $unit eq 'MB' ) {
            'format_bytes';
        }
        elsif ( $unit eq '%' ) {
            'percent';
        }
        else {
            die "Unrecognized unit for $key: “$unit”";    #sanity
        }
    };

    $stat->{'id'} ||= $key;

    my $available_apps_hr = _get_available_apps();

    my $app_info_hr = Cpanel::DynamicUI::App::get_application_from_available_applications( $available_apps_hr, $stat->{'id'} );
    if ($app_info_hr) {
        @{$stat}{ 'description', 'url' } = (
            $stat->{description} || $app_info_hr->{'itemdesc'},
            ( $app_info_hr->{'url'} // q<> ),
        );
    }

    # In v70 we know render these values in the UI so they
    # are localized to the user.  Since JS cannot handle
    # numbers in perl's exponent notation we need to run
    # them though Whostmgr::Math::unsci first.
    if ( length $max && $max =~ tr{eE}{} ) {
        require Whostmgr::Math;
        $max = Whostmgr::Math::unsci($max);
    }

    @{$stat}{ 'maximum', 'usage' } = ( $max, $usage );

    return $stat;
}

sub _get_available_apps {

    #TODO: Use caches for this information
    #such as Cpanel::Template::Plugin::Master’s setup of VarCache.
    return ( $available_apps_hr ||= Cpanel::DynamicUI::App::get_available_applications() );
}

sub _add_custom_usage_stats {
    my ($result_ar) = @_;

    my @mods = Cpanel::LoadModule::Custom::list_modules_for_namespace('Cpanel::ResourceUsage::Custom');

    return if !@mods;

    substr( $_, 0, 0 ) = 'Cpanel::ResourceUsage::Custom::' for @mods;

    my %seen_ids = map { $_->{'id'} => 1 } @$result_ar;

    local $@;
    for my $mod (@mods) {
        eval {
            Cpanel::LoadModule::Custom::load_perl_module($mod);

          NEWSTAT:
            for my $newstat ( $mod->can('get_usages')->($Cpanel::user) ) {
                for my $req ( 'id', 'description', 'usage' ) {
                    if ( !defined $newstat->{$req} ) {
                        die "Need “$req”!";
                    }
                }

                if ( defined $newstat->{'app'} ) {
                    if ( defined $newstat->{'url'} ) {
                        die "$newstat->{'id'}: Give “app” or “url”, not both!";
                    }

                    Cpanel::LoadModule::load_perl_module('Cpanel::Themes');

                    $newstat->{'url'} = Cpanel::Themes::get_user_link_for_app( $Cpanel::user, delete $newstat->{'app'}, 'cpaneld' );

                    # Chop off frontend/$theme/ so that the link works
                    my $theme = Cpanel::Themes::get_user_theme($Cpanel::user);
                    $newstat->{'url'} = substr( $newstat->{'url'}, length("frontend/$theme/") ) if index( $newstat->{'url'}, "frontend/$theme/" ) == 0;
                }

                $newstat->{'formatter'} //= undef;

                if ( $seen_ids{ $newstat->{'id'} } ) {

                    # The id already exists so lets replace the item
                    for my $idx ( 0 .. $#$result_ar ) {
                        if ( $result_ar->[$idx]{'id'} eq $newstat->{'id'} ) {
                            splice @$result_ar, $idx, 1, $newstat;
                            next NEWSTAT;
                        }
                    }
                }

                my $before = delete $newstat->{'before'};
                my $after  = delete $newstat->{'after'};

                my ( $referent, $after_yn );

                if ( defined $before ) {
                    if ( defined $after ) {
                        die 'Give “before” or “after”, not both!';
                    }

                    $referent = $before;
                }
                elsif ( defined $after ) {
                    $referent = $after;
                    $after_yn = 1;
                }

                if ( defined $referent ) {

                    #An ordered hash module might be useful here if we
                    #were using hundreds of elements, but since this is
                    #probably just a dozen or so in @$result_ar and maybe
                    #1 to 3 from the addon, it’s probably more sensible
                    #just to iterate through.
                    my $idx;
                    for $idx ( 0 .. $#$result_ar ) {
                        next if $result_ar->[$idx]{'id'} ne $referent;

                        #Cool! We found the referent item.
                        #Now place the new item before/after it as requested
                        #and move on to the next new item (if any).
                        $idx += 1 if $after_yn;
                        $seen_ids{ $newstat->{'id'} } = 1;
                        splice @$result_ar, $idx, 0, $newstat;
                        next NEWSTAT;
                    }

                    my $referent_field = $after_yn ? 'after' : 'before';
                    warn "$newstat->{'id'}: “$referent_field” refers to nonexistent stats ID “$referent”!";
                }

                $seen_ids{ $newstat->{'id'} } = 1;
                push @$result_ar, $newstat;
            }
        };

        warn "$mod: $@" if $@;
    }

    return;
}

sub _has_role {
    my ($role) = @_;
    require Cpanel::Server::Type::Profile::Roles;
    return Cpanel::Server::Type::Profile::Roles::are_roles_enabled($role);
}

our %API = (
    get_usages => { allow_demo => 1 },
);

1;

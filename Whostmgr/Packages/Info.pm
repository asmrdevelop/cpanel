package Whostmgr::Packages::Info;

# cpanel - Whostmgr/Packages/Info.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Packages::Info

=head1 DESCRIPTION

This module contains “informational” logic for cPanel & WHM account packages.

=head1 FUNCTIONS

=cut

use Cpanel::Conf                      ();
use Cpanel::Email::Maildir            ();
use Cpanel::Encoder::Tiny             ();
use Cpanel::Features::Load            ();
use Cpanel::Locale::Utils::Display    ();
use Cpanel::Server::Type              ();
use Whostmgr::ACLS                    ();
use Whostmgr::Func                    ();
use Whostmgr::Packages::Info::Modular ();

use Locale::Maketext::Utils::MarkPhrase ();

use Cpanel::Imports;

my $cp_defaults;

=head2 %defaults = get_defaults()

Returns a list of key/value pairs that represent default values for
cPanel & WHM packages. The keys correspond to the “pkgref” format,
and the values are hash references:

=over

=item * C<type> - C<boolean>, C<numeric>, or C<string>

=item * C<default> - The default value. (C<n> or C<y> for type C<boolean>)

=item * C<label> - A phrase that will be passed through L<Cpanel::Locale>’s
C<makevar()> method to describe the package entry to the WHM operator.

=item * C<allow_acl> - (OPTIONAL) The ACL required to customize this value.

=item * C<unlimited_acl> - (OPTIONAL) The ACL required to set this value
to unlimited. (Usually represented by 0 or the string C<unlimited>.)

=item * C<validate> - (OPTIONAL) A code reference that returns 1 or 0
to indicate if the given value is valid.

=item * C<limited_default> - (OPTIONAL) A default value that supersedes the
C<defaeult> if the WHM operator doesn’t have the ACL indicated by
C<unlimited_acl>.

=back

NB: This code predates the above descriptions. Please correct any
inaccuracies that you may find.

=cut

sub get_defaults {

    # Avoid loading default until calls so they don't get saved
    # with perlcc
    $cp_defaults ||= Cpanel::Conf->new();

    # We never pass this to anything so we do not have to be concerned about
    # passing a reference that will get modified so we can avoid a copy of
    # the hash which is expensive. This needs to call CpConfGuard directly
    # rather than LoadCpConf so it can validate missing keys.
    require Cpanel::Config::CpConfGuard;
    my $cpconf = Cpanel::Config::CpConfGuard->new();
    my $conf   = $cpconf->{'data'} || $cpconf->{'cache'} || {};

    # The 'label' field is ultimately makevar()d in whostmgr/docroot/templates/pkgform.tmpl
    my %defaults = (
        'ip' => {
            'type'      => 'boolean',
            'default'   => 'n',
            'label'     => Locale::Maketext::Utils::MarkPhrase::translatable('Dedicated IP'),
            'allow_acl' => 'add-pkg-ip',
        },
        'cgi' => {
            'type'    => 'boolean',
            'default' => 'y',
            'label'   => Locale::Maketext::Utils::MarkPhrase::translatable('CGI Access'),
        },
        'digestauth' => {
            'type'    => 'boolean',
            'default' => 'n',
            'label'   => Locale::Maketext::Utils::MarkPhrase::translatable('Digest Authentication at account creation.'),
        },
        'hasshell' => {
            'type'      => 'boolean',
            'default'   => 'n',
            'label'     => Locale::Maketext::Utils::MarkPhrase::translatable('Shell Access'),
            'allow_acl' => 'add-pkg-shell',
        },
        'maxftp' => {
            'type'          => 'numeric',
            'default'       => 'unlimited',
            'label'         => Locale::Maketext::Utils::MarkPhrase::translatable('Max FTP Accounts'),
            'unlimited_acl' => 'allow-unlimited-pkgs',
        },
        'maxsql' => {
            'type'          => 'numeric',
            'default'       => 'unlimited',
            'label'         => Locale::Maketext::Utils::MarkPhrase::translatable('Max SQL Databases'),
            'unlimited_acl' => 'allow-unlimited-pkgs',
        },
        'maxpop' => {
            'type'          => 'numeric',
            'default'       => 'unlimited',
            'label'         => Locale::Maketext::Utils::MarkPhrase::translatable('Max Email Accounts'),
            'unlimited_acl' => 'allow-unlimited-pkgs',
        },
        'maxlst' => {
            'type'          => 'numeric',
            'default'       => 'unlimited',
            'label'         => Locale::Maketext::Utils::MarkPhrase::translatable('Max Mailing Lists'),
            'unlimited_acl' => 'allow-unlimited-pkgs',
        },
        'maxsub' => {
            'type'          => 'numeric',
            'default'       => 'unlimited',
            'label'         => Locale::Maketext::Utils::MarkPhrase::translatable('Max Sub Domains'),
            'unlimited_acl' => 'allow-unlimited-pkgs',
        },
        'max_email_per_hour' => {
            'type'      => 'numeric',
            'default'   => 'unlimited',
            'label'     => Locale::Maketext::Utils::MarkPhrase::translatable('Maximum Hourly Email by Domain Relayed'),
            'allow_acl' => 'allow-emaillimits-pkgs',
        },
        'max_team_users' => {
            'type'      => 'numeric',
            'id'        => 'max_team_users',
            'min'       => '0',
            'max'       => $Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES,
            'default'   => $Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES,
            'label'     => Locale::Maketext::Utils::MarkPhrase::translatable('Max Team Users with Roles'),
            'hide'      => !Cpanel::Server::Type::has_feature('teams'),
            'help_text' => Locale::Maketext::Utils::MarkPhrase::translatable('The Manage Team feature must be enabled in the selected feature list.'),
        },
        'max_defer_fail_percentage' => {
            'type'      => 'numeric',
            'default'   => 100,
            'min'       => 1,
            'max'       => 100,
            'label'     => Locale::Maketext::Utils::MarkPhrase::translatable('Maximum percentage of failed or deferred messages a domain may send per hour'),
            'allow_acl' => 'allow-emaillimits-pkgs',
        },
        'maxpark' => {
            'type'          => 'numeric',
            'default'       => '0',
            'label'         => Locale::Maketext::Utils::MarkPhrase::translatable('Max Parked Domains'),
            'unlimited_acl' => 'allow-unlimited-pkgs',
            'allow_acl'     => 'allow-parkedcreate',
        },
        'maxaddon' => {
            'type'          => 'numeric',
            'default'       => '0',
            'label'         => Locale::Maketext::Utils::MarkPhrase::translatable('Max Addon Domains'),
            'unlimited_acl' => 'allow-unlimited-pkgs',
            'allow_acl'     => 'allow-addoncreate',
        },
        'maxpassengerapps' => {
            'type'          => 'numeric',
            'default'       => 4,
            'label'         => Locale::Maketext::Utils::MarkPhrase::translatable('Max [asis,Passenger] Applications'),
            'unlimited_acl' => 'allow-unlimited-pkgs',
        },

        # NB: We store “unlimited” as 0 in the cpuser file. Thus, we should
        # only allow 0 here in APIs that historically have allowed it as an
        # alias for “unlimited”.
        #
        'bwlimit' => {
            'type'            => 'numeric',
            'min'             => 1,
            'default'         => 'unlimited',
            'label'           => Locale::Maketext::Utils::MarkPhrase::translatable('Monthly Bandwidth Limit (MB)'),
            'unlimited_acl'   => 'allow-unlimited-bw-pkgs',
            'limited_default' => $conf->{'default_pkg_bwlimit'}
        },
        'quota' => {
            'type'            => 'numeric',
            'min'             => 1,
            'default'         => 'unlimited',
            'label'           => Locale::Maketext::Utils::MarkPhrase::translatable('Disk Space Quota (MB)'),
            'unlimited_acl'   => 'allow-unlimited-disk-pkgs',
            'limited_default' => $conf->{'default_pkg_quota'}
        },
        'cpmod' => {
            'type'     => 'string',
            'default'  => $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME,
            'label'    => Locale::Maketext::Utils::MarkPhrase::translatable('cPanel Theme'),
            'validate' => sub {
                my $value = shift;
                $value =~ s/\///g;
                if ( $value !~ m/^\.{1,2}$/ && $value !~ tr/\0// && -d '/usr/local/cpanel/base/frontend/' . $value ) {
                    return 1;
                }
                return;
            },
        },
        'language' => {
            'type'     => 'string',
            'default'  => 'en',
            'label'    => Locale::Maketext::Utils::MarkPhrase::translatable('Locale'),
            'validate' => sub {
                my $value = shift;
                $value =~ s/\///g;
                my $language_for_locale = Cpanel::Locale::Utils::Display::get_locale_menu_hashref(locale);
                if ( $value !~ m/^\.{1,2}$/ && exists $language_for_locale->{$value} ) {
                    return 1;
                }
                return;
            },
        },
        'featurelist' => {
            'type'     => 'string',
            'default'  => 'default',
            'label'    => Locale::Maketext::Utils::MarkPhrase::translatable('Feature List'),
            'validate' => sub {
                my $value = shift;
                $value =~ s/\///g;
                if ( $value eq 'default' || $value eq 'disabled' || ( $value !~ m/\.cpaddons$/ && Cpanel::Features::Load::is_feature_list($value) ) ) {
                    return 1;
                }
                return;
            },
        },
        'max_emailacct_quota' => {
            'type'            => 'numeric',
            'min'             => 1,
            'default'         => 'unlimited',
            'label'           => Locale::Maketext::Utils::MarkPhrase::translatable('Max Quota per Email Address (MB)'),
            'unlimited_acl'   => 'allow-unlimited-pkgs',
            'validate'        => \&_validate_max_emailacct_quota,
            'limited_default' => $conf->{'default_pkg_max_emailacct_quota'},
        },
    );

    for my $val_hr ( values %defaults ) {
        next if $val_hr->{'type'} ne 'numeric';
        $val_hr->{'min'} ||= 0;
    }

    # updating the cpmod default with root or reseller default theme preference
    $defaults{'cpmod'}{'default'} = $cp_defaults->cpanel_theme;
    return %defaults;
}

# Removed as it breaks killacct
# Whostmgr::ACLS::init_acls();

=head2 $DEFAULTS_HR = get_package_items()

Applies ACL checks to the result of C<get_defaults()>.

The following boolean values are added:

=over

=item * C<allowed> - Whether the WHM operator has the field’s C<allow_acl>.
Also true if the field has no C<allow_acl>.

=item * C<can_unlimited> - Whether the WHM operator is authorized
to create a package where the given value is unlimited.

=back

Additionally, if C<can_unlimited> is set to false and if the field’s
C<default> is an unlimited value, that C<default> is set to the field’s
C<limited_default> instead, or to 0 if there is no C<limited_default>.

=cut

sub get_package_items {
    my %my_defaults = get_defaults();

    _augment_defaults_with_modular( \%my_defaults );

    for my $item ( keys %my_defaults ) {
        my $cur = $my_defaults{$item};

        $cur->{'allowed'} = !$cur->{'allow_acl'} || Whostmgr::ACLS::checkacl( $cur->{'allow_acl'} );

        if ( $cur->{'type'} =~ m{num} && !defined $cur->{'can_unlimited'} ) {
            $cur->{'can_unlimited'} = !$cur->{'max'};

            if ( my $unlimited_acl = $cur->{'unlimited_acl'} ) {
                $cur->{'can_unlimited'} &&= Whostmgr::ACLS::checkacl($unlimited_acl);
            }

            # If the reseller can’t create a given field as unlimited,
            # but the field’s default value is unlimited, set a usable
            # default value.
            #
            if ( !$cur->{'can_unlimited'} && $cur->{'default'} && $cur->{'default'} eq 'unlimited' ) {
                $cur->{'default'} = $cur->{'limited_default'} || 0;
            }
        }
    }

    return wantarray ? %my_defaults : \%my_defaults;
}

#----------------------------------------------------------------------

=head2 @result = validate_package_options( $VALUES_HR, $SET_DEFAULTS_YN )

Validates $VALUES_HR against the values that C<get_defaults()> returns.
C<numeric>- and C<string>-type value are tested against their respective
C<validate> logic.

If $SET_DEFAULTS_YN is truthy, then any entries missing from $VALUES_HR
will be set to their C<default> values.

B<IMPORTANT: This does NOT check ACLs!> It will allow,
for example, any C<numeric> value to be set to C<unlimited>.

Numbers receive some special handling (prior to the C<validate>):

=over

=item * The string C<default> is replaced with the field’s C<default>
value. (This happens regardless of $SET_DEFAULTS_YN.)

=item * The string C<n> is converted to 0.

=back

This alters $VALUES_HR in-place. In list context it returns a two-member list,
either:

=over

=item * If everything was valid or missing: a truthy value and a (constant)
message.

=item * Otherwise: a falsy value and a newline-joined list of error strings,
HTML-encoded.

=back

In scalar context it returns the first item of the two-member list that
would be returned in list context.

NB: This code predates the above descriptions. Please correct any
inaccuracies that you may find.

=cut

sub _augment_defaults_with_modular ($defaults_hr) {
    for my $component ( Whostmgr::Packages::Info::Modular::get_enabled_components() ) {
        $defaults_hr->{ $component->name_in_api() } = {
            type    => $component->type(),
            default => $component->default(),

            validate => sub ($specimen) {
                return !$component->why_invalid($specimen);
            },

            # These inform the UI.
            min => $component->minimum(),
            max => $component->maximum(),

            label     => $component->label_var(),
            help_text => $component->help_text_var(),
        };
    }

    return;
}

sub validate_package_options {
    my $opts         = shift;
    my $set_defaults = shift;

    my %defaults = get_defaults();

    my @validation_errors;

    for my $component ( Whostmgr::Packages::Info::Modular::get_disabled_components() ) {
        my $name = $component->name_in_api();

        if ( defined $opts->{$name} ) {
            push @validation_errors, locale()->maketext( 'This server cannot accept “[_1]”.', $name );
        }
    }

    _augment_defaults_with_modular( \%defaults );

    foreach my $pkg_item ( keys %defaults ) {
        my $cfg = $defaults{$pkg_item};

        if ( !length $opts->{$pkg_item} ) {
            if ($set_defaults) {
                $opts->{$pkg_item} = $cfg->{'default'};
            }

            next;
        }

        if ( $cfg->{'type'} eq 'boolean' ) {
            $opts->{$pkg_item} = Whostmgr::Func::yesno( $opts->{$pkg_item} );
        }
        elsif ( $cfg->{'type'} eq 'numeric' ) {
            if ( $opts->{$pkg_item} =~ m/^\Qdefault\E$/i ) {
                $opts->{$pkg_item} = $cfg->{'default'};
            }
            elsif ( $opts->{$pkg_item} eq 'n' ) {
                $opts->{$pkg_item} = 0;
            }
            elsif ( $opts->{$pkg_item} !~ m/^\d+$/ ) {
                if ( $opts->{$pkg_item} !~ m/unlimited/i ) {
                    my $html_safe_value = Cpanel::Encoder::Tiny::safe_html_encode_str( $opts->{$pkg_item} );
                    push @validation_errors, locale->maketext( "Invalid numeric value “[_1]” for the “[_2]” setting.", $html_safe_value, $pkg_item );
                }
            }
            else {
                my $specimen = $opts->{$pkg_item};

                my $is_invalid = $cfg->{'validate'} && !$cfg->{'validate'}->($specimen);

                $is_invalid ||= defined( $cfg->{'min'} ) && ( $specimen < $cfg->{'min'} );
                $is_invalid ||= defined( $cfg->{'max'} ) && ( $specimen > $cfg->{'max'} );

                if ($is_invalid) {
                    my $html_safe_value = Cpanel::Encoder::Tiny::safe_html_encode_str( $opts->{$pkg_item} );
                    push @validation_errors, locale->maketext( "Invalid value “[_1]” for the “[_2]” setting.", $html_safe_value, $pkg_item );
                }
            }
        }
        elsif ( $cfg->{'type'} eq 'string' ) {
            if ( !$cfg->{'validate'}->( $opts->{$pkg_item} ) ) {
                my $html_safe_value = Cpanel::Encoder::Tiny::safe_html_encode_str( $opts->{$pkg_item} );
                push @validation_errors, locale->maketext( "Invalid value “[_1]” for the “[_2]” setting.", $html_safe_value, $pkg_item );
            }
        }
    }

    # NB: These uses of wantarray predate our proscription against its use.
    #
    if (@validation_errors) {
        return wantarray ? ( 0, join( "\n", @validation_errors, q<> ) ) : 0;    ## no critic qw(Wantarray)
    }
    return wantarray ? ( 1, 'Package values accepted' ) : 1;                    ## no critic qw(Wantarray)
}

sub _validate_max_emailacct_quota {
    return $_[0] >= 1 && $_[0] <= Cpanel::Email::Maildir::get_max_email_quota_mib();
}

sub is_valid_package_name {
    my $name = shift;

    return 0 if $name =~ tr{/\r\n\0}{};
    return 0 if $name =~ m{\A\.{1,2}\z};
    return 0 if $name =~ m{\.cache\z};
    return 0 if $name =~ m{\Aextensions\z};
    return 1;
}

1;

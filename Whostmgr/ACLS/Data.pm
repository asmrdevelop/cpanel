package Whostmgr::ACLS::Data;

# cpanel - Whostmgr/ACLS/Data.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::ACLS::Data - Information about WHM’s ACLs

=head1 SYNOPSIS

    Whostmgr::ACLS::Data::add_additional(
        title => 'The Group Name',
        acls => [
            {
                key => 'acl-key',
                title => 'Some ACL Title',
            },
            #...
        ],
    );

    my @categories = Whostmgr::ACLS::Data::CATEGORIES();

=head1 DESCRIPTION

This module houses information about WHM’s ACLs.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::LocaleString ();
use Cpanel::Server::Type ();

use constant REQUIRED_FOR_ADDITIONAL => qw( title acls );
use constant REQUIRED_FOR_ADDTL_ACL  => qw( key title );

my $base_acls = {
    'list-accts' => {
        'title'       => Cpanel::LocaleString->new('List Accounts'),
        'category'    => 'standardprivileges',
        'subcategory' => 'accountinformation',
    },
    'show-bandwidth' => {
        'title'       => Cpanel::LocaleString->new('View Account Bandwidth Usage'),
        'category'    => 'standardprivileges',
        'subcategory' => 'accountinformation',
    },
    'create-acct' => {
        'title'              => Cpanel::LocaleString->new('Create Accounts'),
        'category'           => 'standardprivileges',
        'subcategory'        => 'accountmanagement_standard',
        'multiuser_required' => 1,
    },
    'kill-acct' => {
        'title'              => Cpanel::LocaleString->new('Terminate Accounts'),
        'category'           => 'standardprivileges',
        'subcategory'        => 'accountmanagement_standard',
        'multiuser_required' => 1,
    },
    'suspend-acct' => {
        'title'              => Cpanel::LocaleString->new('Suspend/Unsuspend Accounts'),
        'category'           => 'standardprivileges',
        'subcategory'        => 'accountmanagement_standard',
        'multiuser_required' => 1,
    },
    'upgrade-account' => {
        'title'              => Cpanel::LocaleString->new('Upgrade/Downgrade Accounts'),
        'category'           => 'standardprivileges',
        'subcategory'        => 'accountmanagement_standard',
        'multiuser_required' => 1,
    },
    'ssl' => {
        'title'       => Cpanel::LocaleString->new('[output,abbr,SSL,Secure Sockets Layer] Site Management'),
        'category'    => 'standardprivileges',
        'subcategory' => 'accountmanagement_standard',
        'dnsonly'     => 1,
    },
    'ssl-buy' => {
        'title'       => Cpanel::LocaleString->new('Purchase [output,abbr,SSL,Secure Sockets Layer] Certificates'),
        'category'    => 'standardprivileges',
        'subcategory' => 'accountmanagement_standard',
    },
    'ssl-gencrt' => {
        'title'       => Cpanel::LocaleString->new('[output,abbr,SSL,Secure Sockets Layer] [output,abbr,CSR,Certificate Signing Request]/Certificate Generator'),
        'category'    => 'standardprivileges',
        'subcategory' => 'accountmanagement_standard',
    },
    'edit-mx' => {
        'title'       => Cpanel::LocaleString->new('Edit [output,abbr,MX,Mail eXchange] Entries'),
        'category'    => 'standardprivileges',
        'subcategory' => 'accountmanagement_standard',
    },
    'passwd' => {
        'title'                      => Cpanel::LocaleString->new('Change Passwords'),
        'description'                => Cpanel::LocaleString->new('[output,strong,Warning:] This allows an [asis,API] token user to change account passwords and login with the new password'),
        'category'                   => 'standardprivileges',
        'subcategory'                => 'accountmanagement_standard',
        'description_is_warning'     => 1,
        'warning_manage_tokens_only' => 1,
        'dnsonly'                    => 1,
    },
    'create-dns' => {
        'title'       => Cpanel::LocaleString->new('Add [asis,DNS] Zones'),
        'category'    => 'standardprivileges',
        'subcategory' => 'dns',
        'dnsonly'     => 1,
    },
    'kill-dns' => {
        'title'       => Cpanel::LocaleString->new('Remove [asis,DNS] Zones'),
        'category'    => 'standardprivileges',
        'subcategory' => 'dns',
        'dnsonly'     => 1,
    },
    'park-dns' => {
        'title'       => Cpanel::LocaleString->new('Park [asis,DNS] Zones'),
        'category'    => 'standardprivileges',
        'subcategory' => 'dns',
    },
    'edit-dns' => {
        'title'       => Cpanel::LocaleString->new('Edit [asis,DNS] Zones'),
        'category'    => 'standardprivileges',
        'subcategory' => 'dns',
    },
    'add-pkg' => {
        'title'       => Cpanel::LocaleString->new('Add/Remove Packages'),
        'category'    => 'standardprivileges',
        'subcategory' => 'packages',
    },
    'edit-pkg' => {
        'title'       => Cpanel::LocaleString->new('Edit Packages'),
        'category'    => 'standardprivileges',
        'subcategory' => 'packages',
    },
    'thirdparty' => {
        'title'       => Cpanel::LocaleString->new('Manage Third-Party Services'),
        'category'    => 'standardprivileges',
        'subcategory' => 'thirdpartyservices',
    },
    'mailcheck' => {
        'title'       => Cpanel::LocaleString->new('Troubleshoot Mail Delivery'),
        'category'    => 'standardprivileges',
        'subcategory' => 'troubleshooting_standard',
    },
    'news' => {
        'title'       => Cpanel::LocaleString->new('News Modification'),
        'category'    => 'standardprivileges',
        'subcategory' => 'cpanelmanagement',
    },
    'allow-shell' => {
        'title'       => Cpanel::LocaleString->new('Allow Creation of Accounts with Shell Access'),
        'category'    => 'packageprivileges',
        'subcategory' => 'accounts',
    },
    'viewglobalpackages' => {
        'title'                  => Cpanel::LocaleString->new('Use Root Packages'),
        'description'            => Cpanel::LocaleString->new( 'Reseller-specific packages contain a “[_1]” in their name, but root packages do not contain a “[_1]”.', '_' ),
        'category'               => 'packageprivileges',
        'subcategory'            => 'packageaccess',
        'description_is_warning' => 0,
    },
    'assign-root-account-enhancements' => {
        'title'                  => Cpanel::LocaleString->new('Use Root Account Enhancements'),
        'description'            => Cpanel::LocaleString->new('Allow the reseller to assign or unassign Account Enhancements to their accounts.'),
        'category'               => 'standardprivileges',
        'subcategory'            => 'account_enhancement_privileges',
        'description_is_warning' => 0,
    },
    'allow-addoncreate' => {
        'title'       => Cpanel::LocaleString->new('Create Packages with Addon Domains'),
        'category'    => 'packageprivileges',
        'subcategory' => 'packagescreation',
    },
    'allow-parkedcreate' => {
        'title'       => Cpanel::LocaleString->new('Create Packages with Parked (Alias) Domains'),
        'category'    => 'packageprivileges',
        'subcategory' => 'packagescreation',
    },
    'add-pkg-ip' => {
        'title'       => Cpanel::LocaleString->new('Create Packages with a Dedicated [output,abbr,IP,Internet Protocol] Address'),
        'category'    => 'packageprivileges',
        'subcategory' => 'packagescreation',
    },
    'add-pkg-shell' => {
        'title'       => Cpanel::LocaleString->new('Create Packages with Shell Access'),
        'category'    => 'packageprivileges',
        'subcategory' => 'packagescreation',
    },
    'allow-unlimited-pkgs' => {
        'title'       => Cpanel::LocaleString->new('Create Packages with Unlimited Features (for example, email accounts)'),
        'category'    => 'packageprivileges',
        'subcategory' => 'packagescreation',
    },
    'allow-emaillimits-pkgs' => {
        'title'       => Cpanel::LocaleString->new('Create Packages with Custom Email Limits'),
        'category'    => 'packageprivileges',
        'subcategory' => 'packagescreation',
    },
    'allow-unlimited-disk-pkgs' => {
        'title'                  => Cpanel::LocaleString->new('Create Packages with Unlimited Disk Usage'),
        'description'            => Cpanel::LocaleString->new('This option is unavailable because you enabled the [output,strong,Limit accounts creation by Resource Usage] setting.'),
        'category'               => 'packageprivileges',
        'subcategory'            => 'packagescreation',
        'description_is_warning' => 1,
    },
    'allow-unlimited-bw-pkgs' => {
        'title'                  => Cpanel::LocaleString->new('Create Packages with Unlimited Bandwidth'),
        'description'            => Cpanel::LocaleString->new('This option is unavailable because you enabled the [output,strong,Limit accounts creation by Resource Usage] setting.'),
        'category'               => 'packageprivileges',
        'subcategory'            => 'packagescreation',
        'description_is_warning' => 1,
    },
    'status' => {
        'title'       => Cpanel::LocaleString->new('View Server Status'),
        'category'    => 'globalprivileges',
        'subcategory' => 'serverinformation',
        'dnsonly'     => 1,
    },
    'stats' => {
        'title'       => Cpanel::LocaleString->new('View Server Information'),
        'category'    => 'globalprivileges',
        'subcategory' => 'serverinformation',
        'dnsonly'     => 1,
    },
    'restart' => {
        'title'       => Cpanel::LocaleString->new('Restart Services'),
        'category'    => 'globalprivileges',
        'subcategory' => 'services',
        'dnsonly'     => 1,
    },
    'resftp' => {
        'title'       => Cpanel::LocaleString->new('Resynchronize [output,abbr,FTP,File Transfer Protocol] Passwords'),
        'category'    => 'globalprivileges',
        'subcategory' => 'troubleshooting_global',
    },
    'edit-account' => {
        'title'                  => Cpanel::LocaleString->new('Account Modification'),
        'description'            => Cpanel::LocaleString->new('[output,strong,Warning]: This allows a reseller to bypass account creation limits on features such as dedicated [output,abbr,IP,Internet Protocol] addresses and disk usage.'),
        'category'               => 'superprivileges',
        'subcategory'            => 'accountmanagement_super',
        'description_is_warning' => 1,
    },
    'limit-bandwidth' => {
        'title'                  => Cpanel::LocaleString->new('Bandwidth Limit Modification'),
        'description'            => Cpanel::LocaleString->new('[output,strong,Warning:] This allows a reseller to bypass account package limits if you do not use resource limits.'),
        'category'               => 'superprivileges',
        'subcategory'            => 'accountmanagement_super',
        'description_is_warning' => 1,
    },
    'quota' => {
        'title'                  => Cpanel::LocaleString->new('Quota Modification'),
        'description'            => Cpanel::LocaleString->new('[output,strong,Warning:] This allows a reseller to bypass account package limits if you do not use resource limits.'),
        'category'               => 'superprivileges',
        'subcategory'            => 'accountmanagement_super',
        'description_is_warning' => 1,
    },
    'demo-setup' => {
        'title'              => Cpanel::LocaleString->new('Set an Account to be a Demo Account'),
        'category'           => 'superprivileges',
        'subcategory'        => 'accountmanagement_super',
        'multiuser_required' => 1,
    },
    'rearrange-accts' => {
        'title'                  => Cpanel::LocaleString->new('Rearrange Accounts'),
        'description'            => Cpanel::LocaleString->new('Use this to optimize disk usage across disk drives.'),
        'category'               => 'superprivileges',
        'subcategory'            => 'accountmanagement_super',
        'description_is_warning' => 0,
    },
    'clustering' => {
        'title'                  => Cpanel::LocaleString->new('[output,abbr,DNS,Domain Name System] Clustering'),
        'description'            => Cpanel::LocaleString->new('[output,strong,Warning:] This allows a reseller to bypass many [output,abbr,DNS,Domain Name System] zone modification restrictions.'),
        'category'               => 'superprivileges',
        'subcategory'            => 'clustering',
        'description_is_warning' => 1,
        'dnsonly'                => 1,
    },
    'locale-edit' => {
        'title'                  => Cpanel::LocaleString->new('Modify [output,amp] Create Locales'),
        'description'            => Cpanel::LocaleString->new('[output,strong,Warning:] This allows [output,abbr,HTML,HyperText Markup Language] into all [output,asis,cPanel amp() WHM] user interfaces.'),
        'category'               => 'superprivileges',
        'subcategory'            => 'locales',
        'description_is_warning' => 1,
    },
    'all' => {
        'title'                  => Cpanel::LocaleString->new('All Features'),
        'description'            => Cpanel::LocaleString->new('[output,strong,WARNING: COMPLETE ACCESS TO THE ENTIRE SYSTEM!!]'),
        'category'               => 'rootaccess',
        'subcategory'            => 'everything',
        'description_is_warning' => 1,
        'dnsonly'                => 1,
    },

    # These ACLs control endpoints that previously were set to use 'any'
    # as the ACL - basically, these are ACLs that we assign to resellers
    # as part of the 'makereseller' operation.
    'acct-summary' => {
        'title'       => Cpanel::LocaleString->new('Account Summary'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'basic-whm-functions' => {
        'title'       => Cpanel::LocaleString->new('Basic [asis,WHM] Functions'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
        'dnsonly'     => 1,
    },
    'create-user-session' => {
        'title'                      => Cpanel::LocaleString->new('Create User Session'),
        'description'                => Cpanel::LocaleString->new('[output,strong,Warning:] This privilege allows an [asis,API] token user to bypass restrictions that you set on the [asis,API] token.'),
        'category'                   => 'basicprivileges',
        'subcategory'                => 'initialprivs',
        'description_is_warning'     => 1,
        'warning_manage_tokens_only' => 1,
        'default'                    => 1,
        'dnsonly'                    => 1,
    },
    'digest-auth' => {
        'title'       => Cpanel::LocaleString->new('Digest Authentication'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'generate-email-config' => {
        'title'       => Cpanel::LocaleString->new('Generate Mobile Email Configurations'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'manage-api-tokens' => {
        'title'                      => Cpanel::LocaleString->new('Manage [asis,API] Tokens'),
        'description'                => Cpanel::LocaleString->new('[output,strong,Warning:] This privilege allows an [asis,API] token user to bypass restrictions that you set on the [asis,API] token.'),
        'category'                   => 'basicprivileges',
        'subcategory'                => 'initialprivs',
        'description_is_warning'     => 1,
        'default'                    => 1,
        'warning_manage_tokens_only' => 1,
        'dnsonly'                    => 1,
    },
    'manage-oidc' => {
        'title'       => Cpanel::LocaleString->new('Manage [asis,OpenID Connect]'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'manage-styles' => {
        'title'       => Cpanel::LocaleString->new('Manage Styles'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
        'dnsonly'     => 1,
    },
    'mysql-info' => {
        'title'       => Cpanel::LocaleString->new('[asis,MySQL] Information'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'public-contact' => {
        'title'       => Cpanel::LocaleString->new('Public Contact Information'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'ssl-info' => {
        'title'       => Cpanel::LocaleString->new('[asis,SSL] Information'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
        'dnsonly'     => 1,
    },
    'basic-system-info' => {
        'title'       => Cpanel::LocaleString->new('Basic System Information'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
        'dnsonly'     => 1,
    },
    'cors-proxy-get' => {
        'title'       => Cpanel::LocaleString->new('Allow [output,abbr,CORS,Cross-Origin Resource Sharing] [asis,HTTP] Requests'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'cpanel-integration' => {
        'title'       => Cpanel::LocaleString->new('Manage [asis,cPanel] Integration Links'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'list-pkgs' => {
        'title'       => Cpanel::LocaleString->new('List Packages'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'manage-dns-records' => {
        'title'       => Cpanel::LocaleString->new('Manage [asis,DNS] Records'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
        'dnsonly'     => 1,
    },
    'ns-config' => {
        'title'       => Cpanel::LocaleString->new('Nameserver Configuration'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
        'dnsonly'     => 1,
    },
    'track-email' => {
        'title'       => Cpanel::LocaleString->new('Track Email'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
    'file-restore' => {
        'title'       => Cpanel::LocaleString->new('File and Directory Restoration'),
        'category'    => 'standardprivileges',
        'subcategory' => 'accountmanagement_standard',
        'default'     => 0,
    },
    'cpanel-api' => {
        'title'                      => Cpanel::LocaleString->new('Perform [asis,cPanel] [asis,API] and [asis,UAPI] functions through the [asis,WHM] [asis,API]'),
        'description'                => Cpanel::LocaleString->new('[output,strong,Warning:] This privilege allows an [asis,API] token user to bypass restrictions that you set on the [asis,API] token.'),
        'category'                   => 'basicprivileges',
        'subcategory'                => 'initialprivs',
        'default'                    => 1,
        'description_is_warning'     => 1,
        'warning_manage_tokens_only' => 1,
    },
    'connected-applications' => {
        'title'       => Cpanel::LocaleString->new('Configure connected external applications'),
        'category'    => 'basicprivileges',
        'subcategory' => 'initialprivs',
        'default'     => 1,
    },
};

#keyed on group title, then on ACL key; value is ACL title.
my %additional_acls;

#For tests only.
sub _reset_additional {
    %additional_acls = ();
    return;
}

=head2 add_additional( %OPTS )

Add an additional (e.g., third-party) ACL to this module.

C<%OPTS> is:

=over

=item C<title> - The title of the ACL group. (example: C<Account Information>)

The ACL group key derives from the title: turn A-Z to a-z, and remove spaces.

=item C<acls> - An array reference; each item here must be a hash reference with:

=over

=item C<key> - The ACL’s key. (example: C<list-accts>)

=item C<title> - The ACL’s text description. (example: C<List Accounts>)

=back

=back

=cut

sub add_additional {
    my (%opts) = @_;

    if ( my @missing = grep { !length $opts{$_} } REQUIRED_FOR_ADDITIONAL() ) {
        die "Group missing [@missing]";
    }

    for my $acl ( @{ $opts{'acls'} } ) {
        if ( my @lack = grep { !length $acl->{$_} } REQUIRED_FOR_ADDTL_ACL() ) {
            die "ACL missing [@lack]";
        }
    }

    for my $acl ( @{ $opts{'acls'} } ) {
        $additional_acls{ $opts{'title'} }{ $acl->{'key'} } = $acl->{'title'};
    }
    return;
}

sub get_default_acls {
    my $acls = ACLS();
    return [ sort grep { $acls->{$_}->{'default'} } keys %$acls ];
}

# ACLS does not do a deep copy of $base_acls in order to avoid
# generating a new set of LocaleString objects each time.  Callers
# must pay careful attention to not modify the internals of each
# acl.  In the future we may convert them to blessed objects with
# accessors.
sub ACLS {
    my $acls = {%$base_acls};

    if ( Cpanel::Server::Type::is_dnsonly() ) {
        for my $acl_name ( keys %{$acls} ) {
            delete $acls->{$acl_name} if !$acls->{$acl_name}->{'dnsonly'};
        }
    }

    return $acls if not keys %additional_acls;

    require Cpanel::LocaleString::Raw if !$INC{'Cpanel/LocaleString/Raw.pm'};
    foreach my $thirdparty_subcat ( keys %additional_acls ) {
        $acls->{$_} = {
            'title'       => Cpanel::LocaleString::Raw->new( $additional_acls{$thirdparty_subcat}{$_} ),
            'category'    => 'additionalsoftware',
            'subcategory' => $thirdparty_subcat,
        } for keys %{ $additional_acls{$thirdparty_subcat} };
    }
    return $acls;
}

sub ORDERED_CATEGORIES {
    return [
        qw(
          basicprivileges
          standardprivileges
          packageprivileges
          additionalsoftware
          globalprivileges
          superprivileges
          rootaccess
        )
    ];
}

sub CATEGORIES_METADATA {
    return {
        'basicprivileges' => {
            'title'                 => Cpanel::LocaleString->new('Basic Privileges'),
            'description'           => Cpanel::LocaleString->new('The system always assigns these privileges to newly-created reseller accounts.'),
            'ordered_subcategories' => ['initialprivs'],
        },
        'standardprivileges' => {
            'title'                 => Cpanel::LocaleString->new('Standard Privileges'),
            'description'           => Cpanel::LocaleString->new('These privileges are suitable for most reseller accounts.'),
            'ordered_subcategories' => [
                'accountinformation',
                'accountmanagement_standard',
                'dns',
                'packages',
                'thirdpartyservices',
                'troubleshooting_standard',
                'cpanelmanagement',
                'account_enhancement_privileges',
            ],
        },
        'packageprivileges' => {
            'title'                 => Cpanel::LocaleString->new('Package Privileges'),
            'description'           => Cpanel::LocaleString->new('These privileges control limits on reseller account package creation.'),
            'multiuser_required'    => 1,
            'ordered_subcategories' => [
                'accounts',
                'packageaccess',
                'packagescreation',
            ]
        },
        'additionalsoftware' => {
            'title'                 => Cpanel::LocaleString->new('Additional Software'),
            'ordered_subcategories' => [ sort keys %additional_acls ],
        },
        'globalprivileges' => {
            'title'                 => Cpanel::LocaleString->new('Global Privileges'),
            'description'           => Cpanel::LocaleString->new('These privileges are necessary to perform server administration tasks. They are [output,strong,NOT] suitable for most resellers.'),
            'ordered_subcategories' => [
                'serverinformation',
                'services',
                'troubleshooting_global',
            ],
        },
        'superprivileges' => {
            'title'                 => Cpanel::LocaleString->new('Super Privileges'),
            'description'           => Cpanel::LocaleString->new('These privileges bypass many restrictions on configuration changes. They are [output,strong,NOT] suitable for most resellers.'),
            'ordered_subcategories' => [
                'accountmanagement_super',
                'advancedaccountmanagement',
                'clustering',
                'locales',
            ],
        },
        'rootaccess' => {
            'title'                 => Cpanel::LocaleString->new('Root Access'),
            'ordered_subcategories' => [
                'everything',
            ],
        },
    };
}

sub SUB_CATEGORIES {
    my $subcategories_ref = {
        'initialprivs' => {
            'title'                  => Cpanel::LocaleString->new('Initial Privileges'),
            'description'            => Cpanel::LocaleString->new('The system always assigns these privileges to newly-created reseller accounts. If you remove any of these privileges, it may [output,strong,negatively] impact the [asis,WHM] experience of resellers.'),
            'description_is_warning' => 1,
            'ordered_acls'           => [
                qw(
                  acct-summary
                  basic-system-info
                  basic-whm-functions
                  connected-applications
                  cors-proxy-get
                  cpanel-api
                  cpanel-integration
                  create-user-session
                  digest-auth
                  generate-email-config
                  list-pkgs
                  manage-api-tokens
                  manage-dns-records
                  manage-oidc
                  manage-styles
                  mysql-info
                  ns-config
                  public-contact
                  ssl-info
                  track-email
                )
            ],
        },
        'accountinformation' => {
            'title'        => Cpanel::LocaleString->new('Account Information'),
            'ordered_acls' => [
                qw(
                  list-accts
                  show-bandwidth
                )
            ],
        },
        'accountmanagement_standard' => {
            'title'        => Cpanel::LocaleString->new('Account Management'),
            'ordered_acls' => [
                qw(
                  create-acct
                  kill-acct
                  suspend-acct
                  upgrade-account
                  ssl
                  ssl-buy
                  ssl-gencrt
                  edit-mx
                  passwd
                  file-restore
                )
            ],
        },
        'accountmanagement_super' => {
            'title'        => Cpanel::LocaleString->new('Account Management'),
            'ordered_acls' => [
                qw(
                  edit-account
                  limit-bandwidth
                  quota
                  demo-setup
                )
            ],
        },
        'dns' => {
            'title'        => Cpanel::LocaleString->new('[output,abbr,DNS,Domain Name System]'),
            'ordered_acls' => [
                qw(
                  create-dns
                  kill-dns
                  park-dns
                  edit-dns
                )
            ],
        },
        'packages' => {
            'title'              => Cpanel::LocaleString->new('Packages'),
            'multiuser_required' => 1,
            'ordered_acls'       => [
                qw(
                  add-pkg
                  edit-pkg
                )
            ],
        },
        'thirdpartyservices' => {
            'title'        => Cpanel::LocaleString->new('Third-Party Services'),
            'ordered_acls' => [
                qw(
                  thirdparty
                )
            ],
        },
        'troubleshooting_standard' => {
            'title'        => Cpanel::LocaleString->new('Troubleshooting'),
            'ordered_acls' => [
                qw(
                  mailcheck
                )
            ],
        },
        'troubleshooting_global' => {
            'title'        => Cpanel::LocaleString->new('Troubleshooting'),
            'ordered_acls' => [
                qw(
                  resftp
                )
            ],
        },
        'cpanelmanagement' => {
            'title'              => Cpanel::LocaleString->new('cPanel Management'),
            'multiuser_required' => 1,
            'ordered_acls'       => [
                qw(
                  news
                )
            ],
        },
        'accounts' => {
            'title'        => Cpanel::LocaleString->new('Accounts'),
            'ordered_acls' => [
                qw(
                  allow-shell
                )
            ],
        },
        'packageaccess' => {
            'title'        => Cpanel::LocaleString->new('Package Access'),
            'ordered_acls' => [
                qw(
                  viewglobalpackages
                )
            ],
        },
        'packagescreation' => {
            'title'        => Cpanel::LocaleString->new('Package Creation'),
            'ordered_acls' => [
                qw(
                  allow-addoncreate
                  allow-parkedcreate
                  add-pkg-ip
                  add-pkg-shell
                  allow-unlimited-pkgs
                  allow-emaillimits-pkgs
                  allow-unlimited-disk-pkgs
                  allow-unlimited-bw-pkgs
                )
            ],
        },
        'serverinformation' => {
            'title'        => Cpanel::LocaleString->new('Server Information'),
            'ordered_acls' => [
                qw(
                  status
                  stats
                )
            ],
        },
        'services' => {
            'title'        => Cpanel::LocaleString->new('Services'),
            'ordered_acls' => [
                qw(
                  restart
                )
            ],
        },
        'advancedaccountmanagement' => {
            'title'              => Cpanel::LocaleString->new('Advanced Account Management'),
            'multiuser_required' => 1,
            'ordered_acls'       => [
                qw(
                  rearrange-accts
                )
            ],
        },
        'clustering' => {
            'title'        => Cpanel::LocaleString->new('Clustering'),
            'ordered_acls' => [
                qw(
                  clustering
                )
            ],
        },
        'locales' => {
            'title'        => Cpanel::LocaleString->new('Locales'),
            'ordered_acls' => [
                qw(
                  locale-edit
                )
            ],
        },
        'everything' => {
            'title'        => Cpanel::LocaleString->new('Everything'),
            'ordered_acls' => [
                qw(
                  all
                )
            ],
        },
        'account_enhancement_privileges' => {
            'title'        => Cpanel::LocaleString->new('Account Enhancements'),
            'ordered_acls' => [
                qw(
                  assign-root-account-enhancements
                )
            ],
        },
    };
    return $subcategories_ref if not keys %additional_acls;

    require Cpanel::LocaleString::Raw if !$INC{'Cpanel/LocaleString/Raw.pm'};
    return {
        %{$subcategories_ref},

        # thirdparty subcategories
        map {
            $_ => {
                'title'        => Cpanel::LocaleString::Raw->new($_),
                'ordered_acls' => [ sort keys %{ $additional_acls{$_} } ],
            },
        } keys %additional_acls
    };
}

1;

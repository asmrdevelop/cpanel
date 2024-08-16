package Whostmgr::DynamicUI::Loader;

# cpanel - Whostmgr/DynamicUI/Loader.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Imports;

use Whostmgr::ACLS              ();
use Cpanel::DynamicUI::Parser   ();
use Cpanel::DynamicUI::Filter   ();
use Whostmgr::DynamicUI::Filter ();
use Cpanel::License::CompanyID  ();

=head1 DESCRIPTION

Functions to load and parse the dynamicui.conf files

=cut

=head1 SYNOPSIS

    use Whostmgr::DynamicUI::Loader;

     load_dynamicui_conf
        Loads a dynamicui.conf file into an arrayref

=cut

our $VERSION = '1.0';

=head2 load_dynamicui_conf

=head3 Purpose

loads a dynamicui.conf file into an arrayref

=head3 Arguments

=head4 Required

=over

=item 'dui_conf_file': string - full path to the dynamicui.conf file

=back

=head4 Optional

=over

=item 'raw': boolean - whether the data should be grouped by groups and sorted by group order

=back

=head3 Returns

=over

=item An array ref contains the data represented by dynamicui.conf

=back

=cut

sub load_dynamicui_conf ( $dui_conf_file, $raw = undef ) {

    if ( !-e $dui_conf_file ) {
        return;
    }
    elsif ( !-r _ ) {
        logger()->warn("Failed to read: $dui_conf_file: $!");
        return;
    }

    my $dynui_data = Cpanel::DynamicUI::Parser::read_dynamicui_file($dui_conf_file);

    return if $#$dynui_data == -1;

    return $dynui_data if $raw;
    return _group_and_sort_dynui_data($dynui_data);
}

=head2 load_and_filter()

This function takes the name of the configuration file. Returns a hash reference that
represents items listed in the configuration file. This list has already been filtered
using user's ACLs, and other server configurations, such as dnsonly, CLOUDLINUX, etc,
and should contain the following:

=over 4

=item groups

An array of hash references, each representing a group of applications. For example,

    [
        {
            "searchtext":"support"
            "group":"support"
            "dnsonly_ok":"dns"
            "groupdesc":"Support"
            "items":[
                {
                    "acl":"ACL=all"
                    "searchtext":"support create support ticket"
                    "itemdesc":"Create Support Ticket"
                    "dnsonly_ok":"dns"
                    "url":"/scripts7/create_support_ticket"
                    "group":"support"
                }
            ]
        }
    ]

This list may be empty if the user does not have access to any applications.

=back

=cut

our %dynamicui_data_cache;

sub load_and_filter {
    my ($dynamicui_file) = @_;

    if ( $dynamicui_data_cache{$dynamicui_file} ) {
        return $dynamicui_data_cache{$dynamicui_file};
    }

    my $data = load_dynamicui_conf($dynamicui_file);
    return unless $data;

    my @filtered_groups = ();
    my $lh              = locale();
    my $desc_re         = qr{\$LANG\{'?([^'\}]+)'?\}};

    foreach my $group ( @{ $data->{'groups'} } ) {
        if ( check_flags($group) ) {
            if ( $group->{'groupdesc'} && $group->{'groupdesc'} =~ m{$desc_re} ) {
                $group->{'groupdesc'} = $lh->makevar($1);
            }
            push @filtered_groups, $group;
            my @filtered_items = ();
            foreach my $item ( @{ $group->{'items'} } ) {
                if ( check_flags($item) ) {
                    if ( $item->{'itemdesc'} && $item->{'itemdesc'} =~ m{$desc_re} ) {
                        $item->{'itemdesc'} = $lh->makevar($1);
                    }
                    if ( $item->{'description'} && $item->{'description'} =~ m{$desc_re} ) {
                        $item->{'description'} = $lh->makevar($1);
                    }
                    push @filtered_items, $item;
                }
            }
            $group->{'items'} = \@filtered_items;
        }
    }

    $data->{'groups'} = \@filtered_groups;
    $dynamicui_data_cache{$dynamicui_file} = $data;

    return $data;
}

=head2 check_flags()

Takes a hash reference that represents an application or a group of applications.
Returns 1 if the user has access. Returns 0 if the user does not have access.

=cut

sub check_flags ( $item, $user = undef ) {    ## no critic qw(ProhibitExcessComplexity) - refactor needed

    $item //= {};

    my $is_dnsonly = Whostmgr::DynamicUI::Filter::check_flag('dnsonly');

    if ( defined $item->{'dnsonly_ok'} && $item->{'dnsonly_ok'} ne 'dns' && $is_dnsonly ) {
        return 0;
    }

    my $direct     = Cpanel::License::CompanyID::is_cpanel_direct();
    my $company_id = Cpanel::License::CompanyID::get_company_id();
    my $internal   = $company_id && $company_id == 7;
    if ( defined $item->{'direct_only'} && !$direct && !$internal ) {
        return 0;
    }

    return 0 unless Cpanel::DynamicUI::Filter::is_valid_entry($item);

    if ( my $feature = $item->{'feature_flag'} ) {
        require Cpanel::FeatureFlags::Cache;
        return 0 if !Cpanel::FeatureFlags::Cache::is_feature_enabled($feature);
    }

    if ( my $feature = $item->{'experimental'} ) {
        require Cpanel::Deprecation;
        Cpanel::Deprecation::warn_deprecated_with_replacement( 'experimental', 'feature_flag', '%s option is deprecated and will be removed in a future release, use %s option in all new code.' );

        require Cpanel::FeatureFlags::Cache;
        return 0 if !Cpanel::FeatureFlags::Cache::is_feature_enabled($feature);
    }

    if ( !$is_dnsonly ) {

        if ( my $role = delete $item->{'role'} ) {
            require Cpanel::Server::Type::Profile::Roles;
            return 0 unless Cpanel::Server::Type::Profile::Roles::are_roles_enabled($role);
        }

        if ( my $profile = delete $item->{'profile'} ) {
            require Cpanel::Server::Type::Profile;
            return 0 unless Cpanel::Server::Type::Profile::is_valid_for_profile($profile);
        }

    }

    if ( my $service = delete $item->{service} ) {
        require Cpanel::Services::Enabled;
        return 0 if !Cpanel::Services::Enabled::are_provided($service);
    }

    if ( $item->{'sandbox_only'} ) {
        require Cpanel::Logger;
        return 0 if !Cpanel::Logger::is_sandbox();
    }

    if ( my $min_accounts = $item->{'minimum_accounts_needed'} ) {
        require Whostmgr::MinimumAccounts;
        return 0 if !Whostmgr::MinimumAccounts->new()->server_has_at_least($min_accounts);
    }

    if ( $item->{'acl'} ) {
        my @acls = ();

        my @flags = split( /\s*,\s*/, $item->{'acl'} );

        # ACLs are ORs, all other flags are ANDs
        foreach my $flag (@flags) {
            if ( index( $flag, 'ACL=' ) == 0 ) {
                push @acls, $flag;
            }
            else {
                return 0 unless Whostmgr::DynamicUI::Filter::check_flag($flag);
            }
        }

        return 1 unless scalar @acls;

        my $acl_check = \&Whostmgr::ACLS::checkacl;
        if ($user) {
            require Cpanel::Reseller;
            $acl_check = sub { Cpanel::Reseller::hasresellerpriv( $user, @_ ); };
        }

        foreach my $acl (@acls) {
            my ($var) = ( split( m/=/, $acl ) )[1];
            return 1 if $acl_check->($var);
        }

        return 0;
    }

    return 1;
}

sub _group_and_sort_dynui_data ($dynui_data) {

    my ( @raw_groups, %items, @raw );

    foreach my $item (@$dynui_data) {
        if ( $item->{grouporder} ) {
            push @raw_groups, $item;
        }
        elsif ( $item->{itemorder} ) {
            $items{ $item->{group} } ||= {};
            $items{ $item->{group} }{items} ||= [];
            push @{ $items{ $item->{group} }{items} }, $item;
        }
        elsif ( $item->{type} eq 'subitem' ) {
            my $index;
            for my $i ( 1 .. scalar( @{ $items{ $item->{group} }{items} } ) ) {
                my $thing = @{ $items{ $item->{group} }{items} }[ $i - 1 ];
                next if $thing->{itemorder} != $item->{parent};
                $index = $i - 1;
            }

            # If you can't find it, just keep moving, as at least then the page will show "Results of your Request".
            # Probably not the best idea to die here.
            next if !defined($index);
            push @{ $items{ $item->{group} }{items}[$index]{subitems} }, $item;
        }
        elsif ( $item->{type} eq 'raw' ) {
            push @raw, $item;
        }

    }

    my @groups;
    foreach my $group ( sort { $a->{grouporder} <=> $b->{grouporder} } @raw_groups ) {

        $group->{items} = [];

        foreach my $item ( sort { lc $a->{itemdesc} cmp lc $b->{itemdesc} } values @{ $items{ $group->{group} }{items} } ) {
            push @{ $group->{items} }, $item;
        }

        push @groups, $group;
    }

    return {
        'groups' => \@groups,
        'raw'    => \@raw,
    };
}

1;

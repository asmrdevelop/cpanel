package Whostmgr::HTMLInterface::Userlist;

# cpanel - Whostmgr/HTMLInterface/Userlist.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadUserDomains ();
use Whostmgr::AcctInfo::Owner       ();
use Whostmgr::ACLS                  ();
use Cpanel::Locale                  ();
use Cpanel::Template                ();
use Whostmgr::Session               ();

=encoding utf-8

=head1 NAME

Whostmgr::HTMLInterface::Userlist - Legacy HTML user selector template.

=head1 SYNOPSIS

    use Whostmgr::HTMLInterface::Userlist ();

    Whostmgr::HTMLInterface::Userlist::userlist();

=head2 userlist(%opts)

Output the legacy HTML user selector template.

=over 2

=item Input

=over 3

=item C<HASH>

    do_not_include_resellers: Do not output users that are a reseller
    only_resellers: Only output users that are resellers
    show_root: Output root in the user list.

=back

=item Output

=over 3

Nothing is returned, the template is written to STDOUT.

=back

=back

=cut

#This returns a username if that username is for the only cpuser.
#Otherwise, it displays the user-selector template.
sub userlist {
    my (%opts) = @_;

    my $child_workload_accts = get_child_workload_accts();

    my @userlist = @{ _generate_userlist(%opts) };
    if ( not $opts{user_not_required} and 1 == scalar @userlist ) {

        # Do not allow bypass if the one user that exists has child workloads
        my ($user_workload_index) = grep { $_ eq $userlist[0]->{user} } @{$child_workload_accts};
        return $userlist[0]->{user} if !$user_workload_index;
    }
    my $binary   = $Whostmgr::Session::binary || 1;
    my $app_path = $main::prog //= '';

    Cpanel::Template::process_template(
        whostmgr => {
            template_file => 'userlist/index.tmpl',
            data          => {
                page_path             => '/scripts' . ( $binary > 1 ? $binary : '' ) . '/' . $app_path,
                page_title            => $opts{defheader_title},
                app_key               => $opts{app_key},
                form_tag_action_param => $opts{form_tag_action_param} || '',
                user_not_required     => $opts{user_not_required}     || 0,
                userdomains           => [
                    sort { $a->{user} cmp $b->{user} } @userlist,
                ],
                child_workload_accts => $child_workload_accts,
                map { $_ => $opts{$_} } qw(
                  button_text
                  description_text
                  additional_actions
                  form_widget_top
                ),
            },
        },
    );

    return;
}

=head2 get_child_workload_accts(%opts)

Get a list of accounts that are managed by a parent node.

=over 2

=item Output

=over 3

Returns an array reference of unique usernames for
accounts that have child workloads.

=back

=back

=cut

sub get_child_workload_accts {

    require Cpanel::LinkedNode::List;
    my $user_workloads = Cpanel::LinkedNode::List::list_user_workloads();

    require Cpanel::ArrayFunc::Uniq;
    my @child_workload_accts = Cpanel::ArrayFunc::Uniq::uniq( map { $_->{'user'} } @{$user_workloads} );

    return \@child_workload_accts;
}

sub _generate_userlist {
    my (%opts) = @_;

    my @userlist;
    my $resellers = {};
    if ( $opts{do_not_include_resellers} || $opts{only_resellers} ) {
        require Whostmgr::Resellers::List;
        $resellers = Whostmgr::Resellers::List::list();
    }
    eval {
        my %userdomains = Cpanel::Config::LoadUserDomains::loadtrueuserdomains( undef, 1 );
        for my $user ( keys %{ { %userdomains, %{$resellers} } } ) {
            next unless Whostmgr::ACLS::hasroot() or Whostmgr::AcctInfo::Owner::checkowner( $ENV{REMOTE_USER}, $user );
            next if $opts{do_not_include_resellers} and exists $resellers->{$user};
            next if $opts{only_resellers}           and not exists $resellers->{$user};

            push @userlist, { user => $user, domain => $userdomains{$user} };
        }
        push @userlist, { user => 'root', domain => '' }
          if $opts{show_root};
    };
    if ($@) {
        require Cpanel::Debug;
        Cpanel::Debug::log_warn("Unable to generate userlist: $@");
    }

    return \@userlist;
}

1;

package Cpanel::ConfigFiles::Apache::vhost;

# cpanel - Cpanel/ConfigFiles/Apache/vhost.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######################################################################################################
#### This module is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##
######################################################################################################

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::ConfigFiles::Apache::Config  ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::userdata::Load       ();
use Cpanel::WebVhosts::Owner             ();
use Cpanel::HttpUtils::Version           ();
use Cpanel::Debug                        ();
use Cpanel::WildcardDomain               ();
use Cpanel::LoadModule                   ();
use Cpanel::Template::Plugin::Apache     ();

=encoding utf-8

=head1 NAME

Cpanel::ConfigFiles::Apache::vhost - Tools for updating apache vhosts from userdata

=head1 SUBROUTINES

=cut

our $TEMPLATES_DIR = '/var/cpanel/templates';

my $vhostsless_main_data;

# Call with one arg if domain name is not changing, two args if it is
sub replace_vhost {
    my ( $old_domain, $new_domain, $owner ) = @_;

    return if !$old_domain || $old_domain =~ /\.\.|\//;

    $new_domain = $old_domain unless defined($new_domain);    # Wish we could use defined-or ...

    return replace_vhosts( [ { 'new_domain' => $new_domain, 'current_domain' => $old_domain, 'owner' => $owner } ] );
}

#Each vhost is:
#   { current_domain => '..', new_domain => '..', owner => '..' }
sub replace_vhosts {
    my $vhosts_ar = shift;

    if ( !$vhosts_ar || !ref $vhosts_ar ) {
        return ( 0, "An arrayref of vhosts with domains is required for replace_vhosts" );
    }

    return do_multi_return_ops_with_transaction( [ get_refresh_transaction_vhost_op_cr($vhosts_ar) ] );
}

sub get_refresh_transaction_vhost_op_cr {
    my ($vhosts_ar) = @_;
    return sub {
        my ($transaction) = @_;
        return _refresh_transaction_vhosts( $transaction, $vhosts_ar );
    };
}

=head2 do_multi_return_ops_with_transaction

=over

=item INPUT: $ops_crs

An arrayref of coderefs that will be passed the
Cpanel::HttpUtils::Config::Apache object as the
only argument.

Each coderef should return a "multi-return"
We define a "multi-return" as list with the
first element being 0 or 1 and the second
element being a status message.

If first list element is 0, the transaction
will be aborted and the message in the
second list element will be presented.
Any other coderef
following in the arrayref will be skipped.

=item EXAMPLE:

   [
     get_refresh_transaction_vhost_op_cr($vhosts_ar),
     sub {
           my($transaction) = @_;
           my($status,$message) = CODE_TO_OPERATE_ON($transaction);
           return ($status,$message);
     },
     sub {
           my($transaction) = @_;
           return $transaction->CODE_THAT_DOES_A_MULTI_RETURN_IN_Cpanel::HttpUtils::Config::Apache($input);
     },

   ]

=back

=head3 SEE ALSO: Cpanel::OrDie

=cut

sub do_multi_return_ops_with_transaction {
    my ($ops_crs) = @_;

    require Cpanel::Template;                    # PPI USE OK - preload these before locking httpd.conf
    require Cpanel::Template::Plugin::Apache;    # PPI USE OK - preload these before locking httpd.conf

    require Cpanel::HttpUtils::Config::Apache;
    my $transaction = eval { Cpanel::HttpUtils::Config::Apache->new() };
    if ( !$transaction ) {
        return wantarray ? ( 0, $@ ) : 0;
    }

    foreach my $op_cr (@$ops_crs) {

        my ( $ok, $err_msg ) = $op_cr->($transaction);
        if ( !$ok ) {
            _abort_or_warn($transaction);
            return ( 0, $err_msg );
        }
    }

    my ( $save_ok, $save_msg ) = $transaction->save();
    if ( !$save_ok ) {
        _abort_or_warn($transaction);
        return ( 0, $save_msg );
    }

    _close_or_warn($transaction);

    return 1;
}

sub render_vhost {
    my ( $vhost_data, $is_ssl ) = @_;

    require Cpanel::Template;
    my $vhost_type = $is_ssl ? 'ssl_vhost' : 'vhost';
    my $apv        = Cpanel::HttpUtils::Version::get_current_apache_version_key() || 2;
    $apv = 2 if $apv eq '2_2';

    my $global_hr = delete $vhost_data->{'Cpanel::ConfigFiles::Apache::vhost - vhostsless_main_data'};

    my $ext = 'default';

    #NB: Duplicated with:
    #   - Cpanel::Template
    #   - @Cpanel::ConfigFiles::Apache::local::possible_templates
    #
    if ( -e "$TEMPLATES_DIR/apache$apv/$vhost_type.local" ) {
        $ext = 'local';
    }

    my ( $rc, $msg_sr ) = Cpanel::Template::process_template(
        'apache',
        {
            $global_hr ? %{$global_hr} : (),

            # %{$vhost_data}, # ? vhost templates look for some info in 'vhost' and some as its keys ?
            'vhost'         => $vhost_data,
            'template_file' => "$TEMPLATES_DIR/apache$apv/$vhost_type.$ext",
            'includes'      => {},

            # used to safely encode wildcard domains in the apache configuration template
            'wildcard_safe'        => \&Cpanel::WildcardDomain::encode_wildcard_domain,
            'legacy_wildcard_safe' => \&Cpanel::WildcardDomain::encode_legacy_wildcard_domain,
        },
        {},
    );

    if ( !$msg_sr ) {
        die "Empty render for $vhost_data\n";
    }
    elsif ( length $msg_sr && !ref $msg_sr ) {
        die "Empty render for $vhost_data: $msg_sr\n";
    }

    return ( 1, "Render OK", ${$msg_sr} ) if $rc;
    return ( 0, "Render Failed: $msg_sr" );
}

sub _abort_or_warn {
    my ($transaction) = @_;

    return _action_or_warn( $transaction, 'abort' );
}

sub _close_or_warn {
    my ($transaction) = @_;

    return _action_or_warn( $transaction, 'close' );
}

sub _action_or_warn {
    my ( $transaction, $action ) = @_;

    my ( $ok, $msg );

    my $sub = $transaction->can($action);
    if ($sub) {
        ( $ok, $msg ) = $sub->($transaction);
    }
    else {
        $msg = "No action $action exists for $transaction";
    }
    if ( !$ok ) {
        Cpanel::Debug::log_warn("Apache meta-transaction failed to $action(): $msg");
    }

    return ( $ok, $msg );
}

sub update_domains_vhosts {
    my @domains = @_;

    return replace_vhosts( [ map { { 'current_domain' => $_ } } @domains ] );
}

#Each vhost is:
#   { current_domain => '..', new_domain => '..', owner => '..' }
sub _refresh_transaction_vhosts {
    my ( $transaction, $vhosts_ar, $opts_ref ) = @_;

    my %vhost_updates;
    my @not_installed;
    $opts_ref ||= {};

    foreach my $vhost ( @{$vhosts_ar} ) {
        my ( $current_domain, $new_domain, $owner ) = @{$vhost}{qw(current_domain new_domain owner)};

        $new_domain ||= $current_domain;
        if ( $current_domain && $transaction->servername_type_is_active( $current_domain, 'std' ) || $transaction->servername_type_is_active( $current_domain, 'ssl' ) ) {
            $vhost_updates{$new_domain} = { 'servername' => $new_domain, 'current_servername' => $current_domain, 'owner' => $owner };
        }
        elsif ( my $servername = Cpanel::WebVhosts::Owner::get_vhost_name_for_domain_or_undef($current_domain) ) {
            if ( $new_domain eq $current_domain ) {
                $vhost_updates{$servername} = { 'servername' => $servername, 'current_servername' => $servername, 'owner' => $owner };
            }
            elsif ( $current_domain ne $servername ) {
                return ( 0, "_refresh_transaction_vhosts only accepts domains that match the servername line when changing domain names." );
            }
            else {
                # $new_domain ne $current_domain
                $vhost_updates{$new_domain} = { 'servername' => $new_domain, 'current_servername' => $servername, 'owner' => $owner };
            }

        }
        elsif ( Cpanel::Config::userdata::Load::user_has_ssl_domain( 'nobody', $current_domain ) ) {
            $vhost_updates{$current_domain} = { 'servername' => $current_domain, 'current_servername' => $current_domain, 'owner' => 'nobody' };
        }
        elsif ( $opts_ref->{'allow_create'} ) {
            $vhost_updates{$new_domain} = { 'servername' => $new_domain, 'owner' => $owner };
        }
        else {
            push @not_installed, $current_domain;

        }
    }

    if (@not_installed) {
        return ( 0, "_refresh_transaction_vhosts cannot refresh vhosts because the following domains are not installed: " . join( ', ', sort @not_installed ) );
    }

    my ( $status, $statusmsg, $vhost_strings_hr ) = _get_servername_vhosts_as_strings( [ values %vhost_updates ] );

    if ( !$status ) {
        return wantarray ? ( $status, $statusmsg ) : $status;
    }

    #
    # Sorted so replace order is easy to test
    #
    for my $vhost_key ( sort keys %{$vhost_strings_hr} ) {
        my $vhost_as_string = $vhost_strings_hr->{$vhost_key};

        my $servername = $vhost_key;
        my $is_ssl     = $servername =~ s/_SSL$//g;

        # The vhost_as_string that we are about to insert in
        # httpd.conf might be replacing an existing
        # vhost with a different domain due to a domain name
        # change.  We need to lookup the orignal (current)
        # servername in the vhosts_updates hashref to ensure
        # we replace the old one instead of creating a new one
        # completely.
        my $current_servername = $vhost_updates{$servername}->{'current_servername'};

        my ( $ok, $msg );

        if ( $current_servername && $transaction->servername_type_is_active( $current_servername, $is_ssl ? 'ssl' : 'std' ) ) {
            ( $ok, $msg ) = $transaction->replace_vhosts_by_name( $current_servername, $vhost_as_string );
        }
        else {
            ( $ok, $msg ) = $transaction->add_vhost($vhost_as_string);
        }

        if ( !$ok ) {
            return wantarray ? ( 0, $msg ) : 0;
        }
    }

    return 1;
}

=head2 update_users_vhosts(@users)

Update the virtual host entries in httpd.conf for the
passed in users.  All of the users vhost that currently
exist in httpd.conf will be refreshed.  If the vhost is
in userdata but not in httpd.conf, it will NOT be added.

This function ensures that no new vhosts get created.

=cut

sub update_users_vhosts {
    return _update_users_vhosts( { 'allow_create' => 0 }, @_ );
}

=head2 update_or_create_users_vhosts(@users)

Update the virtual host entries in httpd.conf for the
passed in users.  All of the users vhost that currently
exist in httpd.conf will be refreshed.  If the vhost is
in userdata but not in httpd.conf, it will be added.

This funciton is currently used to add all the vhosts
once userdata is fully restored during an account restore.

=cut

sub update_or_create_users_vhosts {
    return _update_users_vhosts( { 'allow_create' => 1 }, @_ );
}

#Accepts a list of users whose vhosts we will refresh.
sub _update_users_vhosts {
    my ( $opts_ref, @users ) = @_;

    require Cpanel::Template;                    # PPI USE OK - preload these before locking httpd.conf
    require Cpanel::Template::Plugin::Apache;    # PPI USE OK - preload these before locking httpd.conf

    require Cpanel::HttpUtils::Config::Apache;
    my $transaction = eval { Cpanel::HttpUtils::Config::Apache->new() };
    if ( !$transaction ) {
        return wantarray ? ( 0, $@ ) : 0;
    }

    #A convenience to avoid writing out $transaction->abort()
    #for each failure case.
    my ( $ok, $error_message ) = _update_users_vhosts_in_apache_conf( $transaction, \@users, $opts_ref );
    if ( !$ok ) {
        _abort_or_warn($transaction);
        return ( 0, $error_message );
    }

    _close_or_warn($transaction);

    return 1;
}

sub _update_users_vhosts_in_apache_conf {
    my ( $transaction, $users_ar, $opts_ref ) = @_;

    my @vhosts;
    for my $user (@$users_ar) {
        my $ud = Cpanel::Config::userdata::Load::load_userdata($user);
        if ( !$ud || !keys %$ud ) {
            Cpanel::LoadModule::loadmodule('Locale') or do {
                return ( 0, "The user “$user” does not exist on this server." );
            };

            my $locale = Cpanel::Locale->get_handle();
            return ( 0, $locale->maketext( 'The user “[_1]” does not exist on this server.', $user ) );
        }

        next if !$ud->{'main_domain'};

        push @vhosts,
          map { { 'current_domain' => $_, 'owner' => $user }, } (
            $ud->{'main_domain'},
            ( $ud->{'sub_domains'} ? @{ $ud->{'sub_domains'} } : () ),
          );
    }

    my ( $refresh_ok, $refresh_msg ) = _refresh_transaction_vhosts( $transaction, \@vhosts, $opts_ref );
    return ( 0, $refresh_msg ) if !$refresh_ok;

    return $transaction->save();
}

sub get_servername_vhosts {
    require Carp;
    die Carp::longmess("Due to a race condition get_servername_vhosts_inside_transaction_inside_transaction must be used instead");
}

# Warning:
#  Do not call get_servername_vhosts_inside_transaction unless you are inside a http transaction
#  as the userdata for the user could disappear wihtout the
#  vhost transaction lock
#
#Returns std, ssl (if SSL is installed)
sub get_servername_vhosts_inside_transaction {
    my ( $httpd_conf_transaction, $servername, $owner ) = @_;

    # $httpd_conf_transaction is only passed to ensure this function
    # is never called outside of a transaction.

    my ( $status, $statusmsg, $vhost_strings_hr ) = _get_servername_vhosts_as_strings( [ { servername => $servername, owner => $owner } ] );
    return ( $status, $statusmsg ) if !$status;

    my @vhost_texts = ( delete $vhost_strings_hr->{$servername} );
    if (%$vhost_strings_hr) {
        push @vhost_texts, $vhost_strings_hr->{"${servername}_SSL"};
    }

    return ( 1, @vhost_texts );
}

sub _domain_owner_lookup {
    my ($domain) = @_;
    return if $domain eq '*';

    my $dom_owner_lookup_hr = ( $Cpanel::AcctUtils::DomainOwner::Tiny::CACHE_IS_SET ? Cpanel::AcctUtils::DomainOwner::Tiny::get_cache() : Cpanel::AcctUtils::DomainOwner::Tiny::build_domain_cache() );

    if ( !$dom_owner_lookup_hr->{$domain} ) {
        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( 'nobody', $domain ) ) {
            return 'nobody';
        }
    }

    return $dom_owner_lookup_hr->{$domain};    # does not autovivify key so no need for exists first
}

#Each servername item is:
#   { servername => '..', owner => '..' }
#If an 'owner' is not provided, we look it up here.
sub _get_servername_vhosts_as_strings {
    my $servernames_ar = shift;

    if ( !ref $servernames_ar ) {
        return ( 0, "An arrayref of servername/owner hashes is required for _get_vhosts_as_strings" );
    }

    $vhostsless_main_data ||= Cpanel::ConfigFiles::Apache::Config::get_config();

    my @vhosts;
    for my $domain_hr (@$servernames_ar) {
        my ( $servername, $owner ) = @{$domain_hr}{qw( servername owner )};

        $owner ||= _domain_owner_lookup($servername);
        if ( !$owner ) {
            return ( 0, "The system failed to find an owner for the domain “$servername”." );
        }

        if ( $owner ne 'nobody' ) {
            push @vhosts, { %$domain_hr, type => 'std' };
        }

        my $needs_ssl = Cpanel::Config::userdata::Load::user_has_ssl_domain( $owner, $servername );

        if ($needs_ssl) {
            push @vhosts, { %$domain_hr, type => 'ssl' };
        }
    }

    my ( $data_status, $data_message, $vhost_data, $vh_domain ) = _get_vhost_data_structs( \@vhosts );
    return ( $data_status, $data_message ) if !$data_status;

    # allow render_vhost to keep its cache between runs.
    Cpanel::Template::Plugin::Apache::clear_glob_cache();
    Cpanel::Template::Plugin::Apache::clear_file_test_cache();
    local $Cpanel::Template::Plugin::Apache::KEEP_GLOB_CACHE      = 1;
    local $Cpanel::Template::Plugin::Apache::KEEP_FILE_TEST_CACHE = 1;

    my %vhost_strings;
    foreach my $vhost (@vhosts) {
        my ( $domain, $type ) = @{$vhost}{qw(servername type)};

        my $is_ssl = $type eq 'ssl' ? 1 : 0;

        my $vhost_key = _get_vhost_key($vhost);
        if ( my $domain_vhost_data = $vhost_data->{$vhost_key} ) {
            $domain_vhost_data->{'Cpanel::ConfigFiles::Apache::vhost - vhostsless_main_data'} = $vhostsless_main_data;
            my ( $render_status, $render_message, $vhost_string ) = render_vhost( $domain_vhost_data, $is_ssl );
            return ( $render_status, $render_message ) if !$render_status;
            $vhost_strings{$vhost_key} = $vhost_string;
        }
        else {
            Cpanel::Debug::log_warn("The domain $domain ($type) does not exist in the vhost data.");
            next;
        }
    }

    return ( 1, 'Vhost Strings Produced', \%vhost_strings );
}

#Each vhost is:
#   { servername => '..', type => 'std'/'ssl', owner => '..' }
sub _get_vhost_data_structs {
    my $vhosts_ar = shift;

    if ( !$vhosts_ar || !ref $vhosts_ar ) {
        return ( 0, "An arrayref of vhosts with domains is required for _get_vhost_data_structs" );
    }

    my %owners;
    my %domains;

    foreach my $vhost ( @{$vhosts_ar} ) {
        my ( $domain, $type ) = @{$vhost}{qw(servername type)};

        if ( !$domain ) {
            return ( 0, "_get_vhost_data_structs requires all requested vhosts have a domain" );
        }

        my $owner = $vhost->{'owner'} || _domain_owner_lookup($domain);
        if ( !$owner ) {
            Cpanel::Debug::log_warn("_get_vhost_data_structs could not lookup domain owner for domain $domain");
            next;
        }
        $owners{$owner} = undef;
        $domains{ _get_vhost_key($vhost) } = undef;
    }

    my %vhosts_h = map { $_->{'servername'} => 1 } @{$vhosts_ar};
    my $vhost_hr = Cpanel::ConfigFiles::Apache::Config::get_hash_for_users_specific_vhosts( [ keys %owners ], \%vhosts_h );

    return ( 0, "_get_vhost_data_structs could not fetch vhost hash for the following vhosts: " . join( ',', keys %vhosts_h ) ) if !$vhost_hr || !keys %{$vhost_hr};

    my $vhost_data = { map { $_ => $vhost_hr->{$_} } keys %domains };

    return ( 1, 'OK', $vhost_data );
}

sub _get_vhost_key {
    my ($vhost_hr) = @_;
    return $vhost_hr->{'servername'} . ( $vhost_hr->{'type'} eq 'ssl' ? '_SSL' : '' );
}

1;

__END__

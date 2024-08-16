
# cpanel - Cpanel/Config/userdata.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Config::userdata;

use strict;
use warnings;

use Cpanel::Autodie                     ();
use Cpanel::Debug                       ();
use Cpanel::CachedDataStore             ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::Config::userdata::Load      ();
use Cpanel::Config::userdata::Utils     ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::FileUtils::Access       ();
use Cpanel::PwCache                 ();
use Cpanel::SafeDir::MK             ();
use Cpanel::ArrayFunc::Uniq         ();
use Cpanel::WildcardDomain::Tiny    ();
use Cpanel::Config::userdata::Guard ();

our $SKIP_CACHE_UPDATE = 1;

sub add_parked_domain_data {
    my $input = shift;
    if ( !$input->{'user'} || !$input->{'parked_domain'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    my $target_domain;
    {
        my $guard = Cpanel::Config::userdata::Guard->new( $input->{'user'}, 'main' );
        my $main  = $guard->data;
        if ( !$main->{'main_domain'} ) {
            require Cpanel::AcctUtils::Domain;
            $main->{'main_domain'} = Cpanel::AcctUtils::Domain::getdomain( $input->{'user'} );
            if ( !$main->{'main_domain'} ) {
                require Cpanel::Logger;
                Cpanel::Logger::cplog( "Unable to determine main domain for user $input->{'user'}", 'warn', __PACKAGE__, 1 );
                return;
            }
        }
        if ( $input->{'domain'} && $input->{'domain'} ne $main->{'main_domain'} ) {
            if ( exists $main->{'addon_domains'}{ $input->{'domain'} } ) {
                $target_domain = $main->{'addon_domains'}{ $input->{'domain'} };
            }
            else {
                $target_domain = $input->{'domain'};
            }
            $main->{'addon_domains'}{ $input->{'parked_domain'} } = $target_domain;
        }
        else {
            $target_domain = $main->{'main_domain'};
            $main->{'parked_domains'} = [ Cpanel::ArrayFunc::Uniq::uniq( @{ $main->{'parked_domains'} }, $input->{'parked_domain'} ) ];
        }

        #The vhost should already exist.
        my $domain_guard     = Cpanel::Config::userdata::Guard->new( $input->{'user'}, $target_domain );
        my $main_data        = $domain_guard->data();
        my @serveralias_list = split m{\s+}, $main_data->{'serveralias'};
        if ( Cpanel::WildcardDomain::Tiny::contains_wildcard_domain( $input->{'parked_domain'} ) ) {
            push @serveralias_list, $input->{'parked_domain'};
        }
        else {
            push @serveralias_list, $input->{'parked_domain'}, "www.$input->{'parked_domain'}", "mail.$input->{'parked_domain'}";
        }
        $main_data->{'serveralias'} = join( q{ }, sort @serveralias_list );

        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $input->{'user'}, $target_domain ) ) {
            my $domain_ssl_guard = Cpanel::Config::userdata::Guard->new_ssl( $input->{'user'}, $target_domain );
            my $main_ssl_data    = $domain_ssl_guard->data();
            $main_ssl_data->{'serveralias'} = $main_data->{'serveralias'};
            $domain_ssl_guard->save();
        }

        $domain_guard->save();
        $guard->save();
    }

    update_cache( $input->{'user'} )
      unless $input->{'no_cache_update'};

    return $target_domain;
}

sub remove_parked_domain_data {
    my $input = shift;
    if ( !$input->{'user'} || !$input->{'parked_domain'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }
    my $target_domain;
    {
        my $guard = Cpanel::Config::userdata::Guard->new( $input->{'user'}, 'main' );
        my $main  = $guard->data;
        if ( !$main->{'main_domain'} ) {
            require Cpanel::AcctUtils::Domain;
            $main->{'main_domain'} = Cpanel::AcctUtils::Domain::getdomain( $input->{'user'} );
            if ( !$main->{'main_domain'} ) {
                require Cpanel::Logger;
                Cpanel::Logger::cplog( "Unable to determine main domain for user $input->{'user'}", 'warn', __PACKAGE__, 1 );
                $guard->abort();
                return;
            }
        }
        if ( $input->{'domain'} && $input->{'domain'} ne $main->{'main_domain'} ) {
            $target_domain = $input->{'domain'};
            delete $main->{'addon_domains'}{ $input->{'parked_domain'} };
        }
        else {
            $target_domain = $main->{'main_domain'};
            $main->{'parked_domains'} = [ Cpanel::ArrayFunc::Uniq::uniq( grep { $_ ne $input->{'parked_domain'} } @{ $main->{'parked_domains'} } ) ];
        }

        #The vhost should already exist.
        my $domain_guard    = Cpanel::Config::userdata::Guard->new( $input->{'user'}, $target_domain );
        my $modified_domain = 0;
        my $main_data       = $domain_guard->data();
        if ( exists $main_data->{'serveralias'} && $main_data->{'serveralias'} ) {
            my $dom          = $input->{'parked_domain'};
            my $wdom         = 'www.' . $input->{'parked_domain'};
            my $mdom         = 'mail.' . $input->{'parked_domain'};
            my @server_alias = split /\s+/, $main_data->{'serveralias'};
            $main_data->{'serveralias'} = join ' ', Cpanel::ArrayFunc::Uniq::uniq( grep { $_ ne $dom && $_ ne $wdom && $_ ne $mdom } @server_alias );
            $modified_domain            = 1;
        }

        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $input->{'user'}, $target_domain ) ) {
            my $domain_ssl_guard = Cpanel::Config::userdata::Guard->new_ssl( $input->{'user'}, $target_domain );
            my $main_ssl_data    = $domain_ssl_guard->data();
            if ( exists $main_ssl_data->{'serveralias'} && $main_ssl_data->{'serveralias'} ) {
                my $dom          = $input->{'parked_domain'};
                my $wdom         = 'www.' . $input->{'parked_domain'};
                my $mdom         = 'mail.' . $input->{'parked_domain'};
                my @server_alias = split /\s+/, $main_ssl_data->{'serveralias'};
                $main_ssl_data->{'serveralias'} = join ' ', Cpanel::ArrayFunc::Uniq::uniq( grep { $_ ne $dom && $_ ne $wdom && $_ ne $mdom } @server_alias );
                $domain_ssl_guard->save();
            }
        }

        $domain_guard->save() if $modified_domain;
        $guard->save();
    }

    update_cache( $input->{'user'} )
      unless $input->{'no_cache_update'};

    return 1;
}

sub add_addon_domain_data {
    my $input = shift;
    if ( !$input->{'user'} || !$input->{'addon_domain'} || !$input->{'sub_domain'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }
    add_parked_domain_data(
        {
            'user'            => $input->{'user'},
            'parked_domain'   => $input->{'addon_domain'},
            'domain'          => $input->{'sub_domain'},
            'no_cache_update' => $input->{'no_cache_update'},
        }
    );

    return 1;
}

sub remove_addon_domain_data {
    my $input = shift;
    if ( !$input->{'user'} || !$input->{'addon_domain'} || !$input->{'sub_domain'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }
    remove_parked_domain_data(
        {
            'user'            => $input->{'user'},
            'parked_domain'   => $input->{'addon_domain'},
            'domain'          => $input->{'sub_domain'},
            'no_cache_update' => $input->{'no_cache_update'},
        }
    );

    return 1;
}

sub remove_domain_data {
    my $input = shift;

    if ( !$input->{'user'} || !$input->{'domain'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    my $domain = $input->{'domain'};
    $domain =~ s/^www\.//g;

    my $guard       = Cpanel::Config::userdata::Guard->new( $input->{'user'}, 'main' );
    my $main        = $guard->data;
    my $main_domain = $main->{'main_domain'};
    $guard->abort();

    #$main_domain is undef if the user is nobody, but we don't need to
    #check for this for 'nobody' anyway.
    if ( $input->{'user'} ne 'nobody' && $domain eq $main_domain ) {
        return 0;
    }
    elsif ( ref $main->{'parked_domains'} && grep { $domain eq $_ } @{ $main->{'parked_domains'} } ) {
        remove_parked_domain_data(
            {
                'user'            => $input->{'user'},
                'parked_domain'   => $domain,
                'domain'          => $main_domain,
                'no_cache_update' => $input->{'no_cache_update'},
            }
        );
    }
    elsif ( ref $main->{'sub_domains'} && grep { $domain eq $_ } @{ $main->{'sub_domains'} } ) {
        remove_sub_domain_data(
            {
                'user'            => $input->{'user'},
                'sub_domain'      => $domain,
                'no_cache_update' => $input->{'no_cache_update'},
            }
        );
    }
    elsif ( my $sub_domain = $main->{'addon_domains'}->{$domain} ) {
        remove_parked_domain_data(
            {
                'user'            => $input->{'user'},
                'parked_domain'   => $domain,
                'domain'          => $sub_domain,
                'no_cache_update' => $input->{'no_cache_update'},
            }
        );
    }

    return;
}

#Arguments:
#   user (required)
#   sub_domain (required)
#   no_cache_update (optional, boolean)
#   (Additional key/value pairs are saved in the userdata file.)
sub add_sub_domain_data {
    my $input = shift;
    if ( !$input->{'user'} || !$input->{'sub_domain'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }
    {
        my $guard      = Cpanel::Config::userdata::Guard->new( $input->{'user'}, 'main' );
        my $main       = $guard->data();
        my $sub_domain = $input->{'sub_domain'};
        if ( !grep { $_ eq $sub_domain } @{ $main->{'sub_domains'} } ) {
            push @{ $main->{'sub_domains'} }, $sub_domain;
        }
        my $domain_guard = Cpanel::Config::userdata::Guard->new( $input->{'user'}, $input->{'sub_domain'}, { main_data => $main, skip_checking_main_for_new_domain => 1 } );
        my $sub_data     = $domain_guard->data();

        if ( Cpanel::WildcardDomain::Tiny::contains_wildcard_domain( $input->{'sub_domain'} ) ) {
            $sub_data->{'serveralias'} = q<>;
        }
        else {

            #NB: Subdomains do NOT get the “mail.” alias.
            $sub_data->{'serveralias'} = "www.$input->{'sub_domain'}";
        }

        @{$sub_data}{ keys %$input } = values %$input;
        delete @{$sub_data}{qw(addon_domain sub_domain)};
        $sub_data->{'servername'} ||= $input->{'sub_domain'};

        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $input->{'user'}, $input->{'sub_domain'} ) ) {
            my $domain_ssl_guard = Cpanel::Config::userdata::Guard->new_ssl( $input->{'user'}, $input->{'sub_domain'} );
            my $sub_ssl_data     = $domain_ssl_guard->data();

            if ( !Cpanel::WildcardDomain::Tiny::contains_wildcard_domain( $input->{'sub_domain'} ) ) {
                $sub_ssl_data->{'serveralias'} = "www.$input->{'sub_domain'}";
            }

            foreach my $key ( keys %{$input} ) {
                next if ( $key eq 'addon_domain' || $key eq 'sub_domain' );
                $sub_ssl_data->{$key} = $input->{$key};
            }
            $sub_ssl_data->{'ssl'} = 1;
            $sub_ssl_data->{'servername'} ||= $input->{'sub_domain'};
            $domain_ssl_guard->save();
        }

        $domain_guard->save();
        $guard->save();
    }

    update_cache( $input->{'user'} )
      unless $input->{'no_cache_update'};

    return 1;
}

sub remove_sub_domain_data {
    return _remove_generic( shift, 'sub_domains', q{}, '_SSL', '.cache', '_SSL.cache' );
}

#Despite the name, this updates *vhost* data, not a domain’s.
#But it’ll do a vhost lookup of the domain.
sub update_domain_datafield {
    my ( $user, $domain, $field, $value ) = @_;
    if ( !$user || !$domain || !$field || !defined $value ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    $domain =~ s/\///g;

    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    if ( -e $userdata_dir . '/' . $user ) {

        #This makes for a fully race-safe session.
        my $guard = Cpanel::Config::userdata::Guard->new( $user, 'main' );

        my $vh_name = Cpanel::Config::userdata::Utils::get_vhost_name_for_domain( $guard->data(), $domain );

        if ( !$vh_name ) {
            require Cpanel::Logger;
            Cpanel::Logger::cplog( 'No userdata for domain: ' . $domain, 'warn', __PACKAGE__, 1 );
            $guard->abort();
            return;
        }

        #We assume here that the vhost’s userdata *does* already exist.
        #(If not we’ll get an exception.)

        # Standard
        my $domain_guard = Cpanel::Config::userdata::Guard->new( $user, $vh_name );
        $domain_guard->data()->{$field} = $value;

        # SSL
        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $vh_name ) ) {
            my $ssl_domain_guard = Cpanel::Config::userdata::Guard->new_ssl( $user, $vh_name );
            $ssl_domain_guard->data()->{$field} = $value;
            $ssl_domain_guard->save();
        }

        $domain_guard->save() if $domain_guard;
        $guard->abort();
        return $vh_name;
    }
    else {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'No userdata available', 'warn', __PACKAGE__, 1 );
        return;
    }
}

sub update_domain_ip_data {
    my ( $user, $domain, $ip, $skip_update_cache ) = @_;

    if ( my $result = update_domain_datafield( $user, $domain, 'ip', $ip ) ) {
        update_cache($user) unless $skip_update_cache;
        return $result;
    }

    return;
}

sub update_domain_phpopenbasedirprotect_data {
    my ( $user, $domain, $phpopenbasedirprotect ) = @_;
    return update_domain_datafield( $user, $domain, 'phpopenbasedirprotect', $phpopenbasedirprotect );
}

sub update_domain_userdirprotect_data {
    my ( $user, $vhost_name, $userdirprotect ) = @_;
    if ( !$user || !$vhost_name || !defined $userdirprotect ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    if ( $vhost_name eq 'DefaultHost' ) {
        if ( -e apache_paths_facade->dir_conf() . '/main' ) {

            # Usage is safe as we own the file and dir
            my $main_ref = Cpanel::CachedDataStore::fetch_ref( apache_paths_facade->dir_conf() . '/main' );
            unless ($main_ref) {
                require Cpanel::Logger;
                Cpanel::Logger::cplog( 'Main apache conf datastore not available', 'warn', __PACKAGE__, 1 );
                return;
            }
            $main_ref->{'defaultvhost'}{'userdirprotect'} = $userdirprotect;

            # Usage is safe as we own the file and dir
            Cpanel::CachedDataStore::store_ref( apache_paths_facade->dir_conf() . 'main', $main_ref );
        }

        # Set the userdirprotect on the main domain file
        # (usually only necessary if SSL is enabled on the main domain)
        my $userdata_main = load_userdata_main($user);         # No need to lock, we don't write.
        my $main_domain   = $userdata_main->{'main_domain'};

        #For normal users there should always be a userdata file for $user,
        #but for “nobody” there isn’t necessarily. (We assign the hostname as
        #that user’s main domain.)
        if ( $user eq 'nobody' && !length $main_domain ) {
            warn "“$user” lacks a main domain in their userdata file.";
        }
        elsif ( Cpanel::Config::userdata::Load::user_has_domain( $user, $main_domain ) ) {
            update_domain_datafield( $user, $main_domain, 'userdirprotect', $userdirprotect );
        }
        elsif ( $user ne 'nobody' ) {
            warn "“$user” lacks a userdata file for the account’s main domain, “$main_domain”.";
        }
    }
    else {
        update_domain_datafield( $user, $vhost_name, 'userdirprotect', $userdirprotect );
    }

    return;
}

sub update_account_owner_data {
    my $input = shift;
    if ( !$input->{'user'} || !exists $input->{'owner'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    my @domains;
    {
        my $updated_main = 0;
        my $guard        = Cpanel::Config::userdata::Guard->new( $input->{'user'}, 'main' );
        my $main         = $guard->data();
        if ( !$main->{'main_domain'} ) {
            require Cpanel::AcctUtils::Domain;
            $main->{'main_domain'} = Cpanel::AcctUtils::Domain::getdomain( $input->{'user'} );
            if ( !$main->{'main_domain'} ) {
                require Cpanel::Logger;
                Cpanel::Logger::cplog( "Unable to determine main domain for user $input->{'user'}", 'warn', __PACKAGE__, 1 );
                return;
            }
            $updated_main = 1;
        }

        push @domains, $main->{'main_domain'};

        # account may not have 'sub_domains', prevent warning
        if ( exists $main->{'sub_domains'} ) {
            push @domains, @{ $main->{'sub_domains'} };
        }

        foreach my $domain (@domains) {
            my $domain_guard;

            if ( -e $userdata_dir . '/' . $input->{'user'} . '/' . $domain ) {
                $domain_guard = Cpanel::Config::userdata::Guard->new( $input->{'user'}, $domain );
                $domain_guard->data()->{'owner'} = $input->{'owner'};
            }

            # SSL
            if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $input->{'user'}, $domain ) ) {
                my $domain_ssl_guard = Cpanel::Config::userdata::Guard->new_ssl( $input->{'user'}, $domain );
                $domain_ssl_guard->data()->{'owner'} = $input->{'owner'};
                $domain_ssl_guard->save();
            }

            $domain_guard->save() if $domain_guard;
        }

        $guard->save() if $updated_main;
    }

    update_cache( $input->{'user'} )
      unless $input->{'no_cache_update'};

    return 1;
}

sub update_homedir_data {
    my $input = shift;
    if ( !$input->{'user'} || !exists $input->{'new_homedir'} || !exists $input->{'old_homedir'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    my @domains;
    {
        my $updated_main = 0;
        my $guard        = Cpanel::Config::userdata::Guard->new( $input->{'user'}, 'main' );
        my $main         = $guard->data();
        if ( !$main->{'main_domain'} ) {
            require Cpanel::AcctUtils::Domain;
            $main->{'main_domain'} = Cpanel::AcctUtils::Domain::getdomain( $input->{'user'} );
            if ( !$main->{'main_domain'} ) {
                require Cpanel::Logger;
                Cpanel::Logger::cplog( "Unable to determine main domain for user $input->{'user'}", 'warn', __PACKAGE__, 1 );
                $guard->abort();
                return;
            }
            $updated_main = 1;

        }
        push @domains, $main->{'main_domain'};
        push @domains, @{ $main->{'sub_domains'} };

        foreach my $domain (@domains) {
            my $domain_guard;
            if ( -e $userdata_dir . '/' . $input->{'user'} . '/' . $domain ) {
                $domain_guard = Cpanel::Config::userdata::Guard->new( $input->{'user'}, $domain );
                my $domain_data = $domain_guard->data();
                $domain_data->{'homedir'} = $input->{'new_homedir'};
                $domain_data->{'documentroot'} =~ s/^\Q$input->{'old_homedir'}\E/$input->{'new_homedir'}/;
                foreach my $scriptalias ( @{ $domain_data->{'scriptalias'} } ) {
                    $scriptalias->{'path'} =~ s/^\Q$input->{'old_homedir'}\E/$input->{'new_homedir'}/;
                }
            }

            # SSL
            if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $input->{'user'}, $domain ) ) {
                my $ssl_domain_guard = Cpanel::Config::userdata::Guard->new_ssl( $input->{'user'}, $domain );
                my $domain_data      = $ssl_domain_guard->data();
                $domain_data->{'homedir'} = $input->{'new_homedir'};
                $domain_data->{'documentroot'} =~ s/^\Q$input->{'old_homedir'}\E/$input->{'new_homedir'}/;
                foreach my $scriptalias ( @{ $domain_data->{'scriptalias'} } ) {
                    $scriptalias->{'path'} =~ s/^\Q$input->{'old_homedir'}\E/$input->{'new_homedir'}/;
                }
                $ssl_domain_guard->save();
            }

            $domain_guard->save() if $domain_guard;
        }

        $guard->save() if $updated_main;
    }

    update_cache( $input->{'user'} )
      unless $input->{'no_cache_update'};

    return 1;
}

sub check_addon_compatibility {
    my (%opts) = @_;

    return 1 unless defined $opts{user} && defined $opts{domain};
    my $guard = Cpanel::Config::userdata::Guard->new( $opts{'user'}, 'main' );
    return 1 unless $guard;
    my $data   = $guard->data();
    my $addons = $data->{'addon_domains'};

    return 1 unless $addons && ref $addons eq ref {} && scalar keys %$addons;
    map { return 0 if m/^\S+\.\Q$opts{domain}\E$/i; } keys %$addons;
    return 1;
}

sub update_domain_name_data {
    my $input = shift;
    if ( !$input->{'user'} || !$input->{'old_domain'} || !$input->{'new_domain'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    my $guard = Cpanel::Config::userdata::Guard->new( $input->{'user'}, 'main' );
    my $main  = $guard->data();
    if ( !$main->{'main_domain'} ) {
        require Cpanel::AcctUtils::Domain;
        $main->{'main_domain'} = Cpanel::AcctUtils::Domain::getdomain( $input->{'user'} );
        if ( !$main->{'main_domain'} ) {
            require Cpanel::Logger;
            Cpanel::Logger::cplog( "Unable to determine main domain for user $input->{'user'}", 'warn', __PACKAGE__, 1 );
            $guard->abort();
            return;
        }
    }

    # Old domain -> New domain mapping
    my %domains;

    if ( $main->{'main_domain'} eq $input->{'old_domain'} || $input->{'update_main_domain'} ) {
        $main->{'main_domain'} = $input->{'new_domain'};
        $domains{ $input->{'old_domain'} } = $input->{'new_domain'};

        # Update subdomains
        my @subs;
        foreach my $sub ( @{ $main->{'sub_domains'} } ) {
            my $is_under_parked_domain = scalar grep { $sub =~ m/^(?:.+)\.\Q$_\E$/ } @{ $main->{'parked_domains'} };
            if ( !$is_under_parked_domain && $sub =~ m/^(\S+)\.\Q$input->{'old_domain'}\E$/i ) {
                my $sub_part = $1;
                $domains{$sub} = $sub_part . '.' . $input->{'new_domain'};
                push @subs, $sub_part . '.' . $input->{'new_domain'};

                # Update addon domain
                foreach my $addon ( keys %{ $main->{'addon_domains'} } ) {
                    next unless defined $main->{'addon_domains'}{$addon};
                    next if $main->{'addon_domains'}{$addon} ne $sub;
                    $main->{'addon_domains'}{$addon} = $sub_part . '.' . $input->{'new_domain'};
                }
                next;
            }
            push @subs, $sub;
        }
        @{ $main->{'sub_domains'} } = @subs;
    }
    else {
        my @subs;
        foreach my $sub ( @{ $main->{'sub_domains'} } ) {
            if ( $sub eq $input->{'old_domain'} ) {
                $domains{$sub} = $input->{'new_domain'};
                next;
            }
            push @subs, $sub;
        }
        push @subs, $input->{'new_domain'};
        @{ $main->{'sub_domains'} } = @subs;

        # Update addon domain
        foreach my $addon ( keys %{ $main->{'addon_domains'} } ) {
            next if $main->{'addon_domains'}{$addon} ne $input->{'old_domain'};
            $main->{'addon_domains'}{$addon} = $input->{'new_domain'};
        }
    }

    foreach my $old_domain ( keys %domains ) {
        _update_userdata_domain( $input->{'user'}, $old_domain, $domains{$old_domain}, 0 );
        _update_userdata_domain( $input->{'user'}, $old_domain, $domains{$old_domain}, 1 );
    }

    $guard->save();

    update_cache( $input->{'user'} )
      unless $input->{'no_cache_update'};

    return 1;
}

sub _update_userdata_domain {

    my ( $user, $old_domain, $new_domain, $is_ssl ) = @_;

    my $ssl_suffix = $is_ssl ? '_SSL' : '';

    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    # skip if no config file
    return unless ( -e $userdata_dir . '/' . $user . '/' . $old_domain . $ssl_suffix );

    # No need to lock, we are just reading
    my $domain_data = load_userdata_domain( $user, $old_domain . $ssl_suffix, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_DO );

    # servername
    $domain_data->{'servername'} = $new_domain;

    # serveralias
    my @new_serveraliases;
    if ( exists $domain_data->{'serveralias'} && $domain_data->{'serveralias'} ) {
        my @serveraliases = split( /\s+/, $domain_data->{'serveralias'} );
        foreach my $alias (@serveraliases) {
            $alias =~ s/\.\Q$old_domain\E$/\.$new_domain/;
            push @new_serveraliases, $alias;
        }
        $domain_data->{'serveralias'} = join ' ', @new_serveraliases;
    }

    # serveradmin
    if ( exists $domain_data->{'serveradmin'} && $domain_data->{'serveradmin'} ) {
        $domain_data->{'serveradmin'} =~ s/\Q$old_domain\E$/$new_domain/i;
    }

    # customlog
    if ( exists $domain_data->{'customlog'} && $domain_data->{'customlog'} ) {
        foreach my $log_line ( @{ $domain_data->{'customlog'} } ) {
            $log_line->{'target'} =~ s/\/\Q$old_domain\E($|-)/\/${new_domain}$1/;
        }
    }

    # SSL specific directives
    my $removed_ssl_certificate = 0;
    if ($is_ssl) {
        require Cpanel::Apache::TLS;

        if ( Cpanel::Apache::TLS->has_tls($old_domain) ) {
            require Cpanel::Apache::TLS::Write;
            require Cpanel::SSL::Objects::Certificate;

            my $cert = ( Cpanel::Apache::TLS->get_tls($old_domain) )[1];
            if ($cert) {
                my $c_obj = Cpanel::SSL::Objects::Certificate->new( cert => $cert );

                # There is avoidable overhead associated with separate calls of
                # valid_for_domain() for multiple domains on the same cert.
                if ( $c_obj && grep { $c_obj->valid_for_domain($_) } $new_domain, @new_serveraliases ) {
                    Cpanel::Apache::TLS::Write->new()->rename( $old_domain => $new_domain );
                }
                else {
                    Cpanel::Apache::TLS::Write->new()->enqueue_unset_tls($old_domain);
                    $removed_ssl_certificate = 1;
                }
            }
        }

        if ( exists $domain_data->{'errorlog'} ) {
            my $old_errorlog = $domain_data->{'errorlog'};
            my $new_errorlog = $domain_data->{'errorlog'};
            $new_errorlog =~ s/\/\Q$old_domain\E-/\/${new_domain}-/;
            $domain_data->{'errorlog'} = $new_errorlog;
        }
    }

    # if we delete the certificate we do not migrate the vhost
    # data since apache will fail if there is no certificate

    unless ($removed_ssl_certificate) {

        # save new config unless we removed the certificate
        save_userdata_domain( $user, $new_domain . $ssl_suffix, $domain_data );
    }

    _remove_files( $user, ( map { "$old_domain$ssl_suffix$_" } ( '', '.cache' ) ) );
    return;
}

sub update_user_name_data {
    my $input = shift;
    if ( !$input->{'old_user'} || !$input->{'new_user'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    if ( !$input->{'new_group'} ) {
        $input->{'new_group'} = getgrgid( ( Cpanel::PwCache::getpwnam_noshadow( $input->{'new_user'} ) )[3] );
        if ( !$input->{'new_group'} ) {
            $input->{'new_group'} = $input->{'new_user'};
        }
    }

    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    # Recover previously failed change
    if ( -e $userdata_dir . '/' . $input->{'new_user'} ) {
        my $dir_rename = !-e $userdata_dir . '/' . $input->{'old_user'} ? $userdata_dir . '/' . $input->{'old_user'} : $userdata_dir . '/' . $input->{'new_user'} . '.' . time;
        require Cpanel::Logger;
        Cpanel::Logger::cplog( "New user $input->{'new_user'} userdata already exists, renaming directory to $dir_rename", 'warn', __PACKAGE__, 1 );
        rename $userdata_dir . '/' . $input->{'new_user'}, $dir_rename;
    }

    if ( -e $userdata_dir . '/' . $input->{'old_user'} ) {
        rename $userdata_dir . '/' . $input->{'old_user'}, $userdata_dir . '/' . $input->{'new_user'};
        if ( !-e $userdata_dir . '/' . $input->{'new_user'} ) {
            require Cpanel::Logger;
            Cpanel::Logger::cplog( "Unable to alter user $input->{'old_user'}", 'warn', __PACKAGE__, 1 );
            return;
        }
    }

    my @domains;
    my $guard        = Cpanel::Config::userdata::Guard->new( $input->{'new_user'}, 'main' );
    my $main         = $guard->data();
    my $updated_main = 0;
    if ( !$main->{'main_domain'} ) {
        $main->{'main_domain'} = Cpanel::AcctUtils::Domain::getdomain( $input->{'old_user'} );
        if ( !$main->{'main_domain'} ) {
            require Cpanel::Logger;
            Cpanel::Logger::cplog( "Unable to determine main domain for user $input->{'old_user'}", 'warn', __PACKAGE__, 1 );
            $guard->abort();
            return;
        }
        $updated_main = 1;
    }
    push @domains, $main->{'main_domain'};
    push @domains, @{ $main->{'sub_domains'} };

    foreach my $domain (@domains) {
        my $domain_guard;
        if ( -e $userdata_dir . '/' . $input->{'new_user'} . '/' . $domain ) {
            $domain_guard = Cpanel::Config::userdata::Guard->new( $input->{'new_user'}, $domain );
            my $domain_data = $domain_guard->data();
            $domain_data->{'user'}  = $input->{'new_user'};
            $domain_data->{'group'} = $input->{'new_group'};
        }
        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $input->{'new_user'}, $domain ) ) {
            my $domain_ssl_guard = Cpanel::Config::userdata::Guard->new_ssl( $input->{'new_user'}, $domain );
            my $domain_data      = $domain_ssl_guard->data();
            $domain_data->{'user'}  = $input->{'new_user'};
            $domain_data->{'group'} = $input->{'new_group'};
            $domain_ssl_guard->save();
        }
        $domain_guard->save() if $domain_guard;
    }

    if ($updated_main) {
        $guard->save();
    }
    else {
        $guard->abort();
    }

    update_cache( $input->{'new_user'} )
      unless $input->{'no_cache_update'};

    return 1;
}

*load_userdata = *Cpanel::Config::userdata::Load::load_userdata;

sub save_userdata {
    my ( $user, $file, $ref, $skip_addon_domain_check ) = @_;

    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    if ( @_ == 2 ) {
        $ref  = $file;
        $file = 'main';
    }
    $file = 'main' if !defined $file;
    return         if !ref $ref;

    if ( !$skip_addon_domain_check && $file ne 'main' ) {
        my $userdata_ref = load_userdata_main($user);
        my $test_file    = ( split( /_SSL$/, $file ) )[0];
        if ( $userdata_ref->{'addon_domains'}->{$test_file} ) {
            $file = $userdata_ref->{'addon_domains'}->{$test_file} . ( ( $file =~ m/_SSL$/ ) ? '_SSL' : '' );
        }
    }

    if ( !eval { Cpanel::FileUtils::Access::ensure_mode_and_owner( "$userdata_dir/$user", 0750, 0, $user ) } ) {
        return if !_ensure_base_userdata_dir();
        return if !_ensure_user_userdata_dir($user);
    }

    # Usage is save as we own the file and dir
    return Cpanel::CachedDataStore::store_ref( "$userdata_dir/$user/$file", $ref );
}

sub _ensure_user_userdata_dir {
    my ($username) = @_;

    my $userdata_dir      = $Cpanel::Config::userdata::Constants::USERDATA_DIR;
    my $user_userdata_dir = "$userdata_dir/$username";

    if ( !Cpanel::Autodie::exists($user_userdata_dir) && !Cpanel::SafeDir::MK::safemkdir( $user_userdata_dir, '0750' ) ) {
        Cpanel::Debug::log_warn("Failed to create user directory in cpanel userdata: $!");
        return;
    }

    Cpanel::FileUtils::Access::ensure_mode_and_owner( $user_userdata_dir, 0750, 0, $username );

    return $user_userdata_dir;
}

sub _ensure_base_userdata_dir {
    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    if ( !Cpanel::Autodie::exists($userdata_dir) && !Cpanel::SafeDir::MK::safemkdir( $userdata_dir, '0711' ) ) {
        Cpanel::Debug::log_warn("Failed to create cpanel userdata directory: $!");
        return;
    }

    Cpanel::FileUtils::Access::ensure_mode_and_owner( $userdata_dir, 0711, 0, 0 );
    return 1;
}

*load_userdata_main = *Cpanel::Config::userdata::Load::load_userdata_main;

*load_userdata_domain = *Cpanel::Config::userdata::Load::load_userdata_domain;

*load_userdata_real_domain = *Cpanel::Config::userdata::Load::load_userdata_real_domain;

sub save_userdata_domain {
    my ( $user, $domain, $ref, $skip_addon_domain_check ) = @_;
    return save_userdata( $user, $domain, $ref, $skip_addon_domain_check );
}

sub save_userdata_domain_ssl {
    my ( $user, $domain, $ref, $skip_addon_domain_check ) = @_;
    return save_userdata( $user, "${domain}_SSL", $ref, $skip_addon_domain_check );
}

sub fix_parked_sub_duplicates_data {
    my ( $hr, $main ) = @_;

    if ( ref $hr ne 'HASH' ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    if ( !exists $hr->{'sub_domains'} || ref $hr->{'sub_domains'} ne 'ARRAY' ) {
        $hr->{'sub_domains'} = [];
    }

    my @keep;
    my $save = 0;
    my %subdom_lookup;
    @subdom_lookup{ @{ $hr->{'sub_domains'} } } = ();

    for my $parkdomain ( @{ $hr->{'parked_domains'} } ) {
        if ( exists $subdom_lookup{$parkdomain} ) {
            print "Fixing $parkdomain in parked_domains\n";    # no output - log instead ??
            $save++;
        }
        else {
            push @keep, $parkdomain;
        }
    }

    $hr->{'parked_domains'} = \@keep;

    if ($save) {
        if ( ref $main ne 'HASH' ) {
            require Cpanel::Logger;
            Cpanel::Logger::cplog( 'Could not fix_parked_sub_duplicates_data() for \"main\" sincve no hashref was passed for it ', 'warn', __PACKAGE__, 1 );
        }
        else {
            $main->{'serveralias'} = 'www.' . $hr->{'main_domain'};
            for my $parked ( @{ $hr->{'parked_domains'} } ) {
                $main->{'serveralias'} .= " $parked www.$parked";
            }
        }
    }

    return 1;
}

# Return a list (or list ref) of all the users in the /var/cpanel/userdata directory
sub load_user_list {

    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    my @users = ();
    if ( opendir my $users_dh, $userdata_dir ) {

        # Get a list of all userdata directories that contain a 'main' file
        @users = grep { !m/^\.+$/ && -r "$userdata_dir/$_/main" } readdir $users_dh;

        closedir $users_dh;
    }
    else {
        Cpanel::Debug::log_warn("Failed to open directory $userdata_dir: $!");
    }

    return wantarray ? @users : \@users;
}

sub load_user_subdomains {
    my $user = shift || $ENV{'USER'};    # default to EUID
    my %result;

    my $userdata_ref = load_userdata_main($user);
    for my $subdomain ( @{ $userdata_ref->{'sub_domains'} } ) {
        my $subdomain_ref = load_userdata( $user, $subdomain );
        if ( 'HASH' eq ref $subdomain_ref ) {
            $result{$subdomain} = $subdomain_ref->{'documentroot'};
        }
    }

    return wantarray ? %result : \%result;
}

sub is_sub_domain {

    # See if the domain matches one of the user's sub-domains
    my ( $user, $domain, $userdata ) = @_;

    $domain =~ tr{A-Z}{a-z};

    if ( !$userdata ) {
        $userdata = load_userdata_main($user);

        if ( !$userdata || ref $userdata ne 'HASH' ) {
            Cpanel::Debug::log_warn("Failed to load userdata for user '$user'.");
            return 0;
        }
    }

    if ( exists $userdata->{'sub_domains'} && ref $userdata->{'sub_domains'} eq 'ARRAY' ) {
        for my $sub_domain ( @{ $userdata->{'sub_domains'} } ) {
            return 1 if ( $domain eq $sub_domain =~ tr{A-Z}{a-z}r );
        }
    }

    return 0;
}

*is_parked_domain = *Cpanel::Config::userdata::Load::is_parked_domain;

*is_addon_domain = *Cpanel::Config::userdata::Load::is_addon_domain;

*get_real_domain = *Cpanel::Config::userdata::Load::get_real_domain;

sub get_domain_type {

    # Treat return value as boolean to determine if the current user owns the domain
    my ( $user, $domain, $userdata ) = @_;

    $domain =~ tr{A-Z}{a-z};

    if ( !$userdata ) {
        $userdata = load_userdata_main($user);

        if ( !$userdata || ref $userdata ne 'HASH' ) {
            Cpanel::Debug::log_warn("Failed to load userdata for user '$user'.");
            return undef;
        }
    }

    if ( $domain eq $userdata->{'main_domain'} ) {
        return 'main';
    }
    if ( is_sub_domain( $user, $domain, $userdata ) ) {
        return 'sub';
    }
    if ( is_parked_domain( $user, $domain, $userdata ) ) {
        return 'parked';
    }
    if ( is_addon_domain( $user, $domain, $userdata ) ) {
        return 'addon';
    }
    return undef;
}

sub update_cache {    ## no critic qw(Subroutines::RequireArgUnpacking)
    require Cpanel::Config::userdata::UpdateCache;
    eval { Cpanel::Config::userdata::UpdateCache::update(@_); };
    if ($@) {
        Cpanel::Debug::log_warn("Error regenerating userdata cache: $@");
    }

    require Cpanel::Config::userdata::Cache;
    Cpanel::Config::userdata::Cache::reset_cache();
    return;
}

sub remove_user_domain_ssl {
    my ( $user, $domain ) = @_;

    return _remove_files(
        $user,
        "${domain}_SSL",
        "${domain}_SSL.cache",
        "www.${domain}_SSL",
        "www.${domain}_SSL.cache",
    );
}

sub change_docroot {
    my $input = shift;
    if ( !$input->{'user'} || !$input->{'domain'} || !$input->{'docroot'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

    my $domain_guard;
    {
        $domain_guard = Cpanel::Config::userdata::Guard->new( $input->{'user'}, $input->{'domain'} );
        my $sub_data = $domain_guard->data();
        $sub_data->{'documentroot'} = $input->{'docroot'};

        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $input->{'user'}, $input->{'domain'} ) ) {
            my $domain_ssl_guard = Cpanel::Config::userdata::Guard->new_ssl( $input->{'user'}, $input->{'domain'} );
            my $sub_ssl_data     = $domain_ssl_guard->data();
            $sub_ssl_data->{'documentroot'} = $input->{'docroot'};
            $domain_ssl_guard->save();
        }

        $domain_guard->save();
    }

    update_cache( $input->{'user'} )
      unless $input->{'no_cache_update'};

    return 1;
}

=head1 SSL REDIRECTS

A variety of domains can be set to automatically redirect to their SSL vhost if autoSSL is configured, and their SSL is currently valid.

Sets this in the domain configuration file.

=head2 add_ssl_redirect_data($input_hashref)

=over 4

=item B<ssl_redirect> - name of the SSL redirect to add.

=item B<user> - name of the user who owns said SSL redirect.

=item B<no_cache_update> - Don't update the userdata cache file.

=back

=head2 remove_ssl_redirect_data($input_hashref)

=over 4

=item B<ssl_redirect> - name of the SSL redirect to remove.

=item B<user> - name of the user who owns said SSL redirect.

=item B<no_cache_update> - Don't update the userdata cache file.

=back

=cut

sub add_ssl_redirect_data {
    return _toggle_https( shift, 1 );
}

sub remove_ssl_redirect_data {
    return _toggle_https( shift, 0 );
}

sub _toggle_https {
    my ( $input, $state ) = @_;

    if ( !$input->{'user'} || !$input->{'ssl_redirect'} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    my $guard = eval { Cpanel::Config::userdata::Guard->new( $input->{'user'}, $input->{ssl_redirect} ) };

    #No need to do anything unless we've got something to configure, which we won't with parks/addons.
    #They inherit from their associated subdomain.
    return 1 unless $guard;

    my $main = $guard->data();

    $main->{ssl_redirect} = !!$state;
    $guard->save();
    update_cache( $input->{'user'} ) unless $input->{'no_cache_update'};
    return 1;
}

#Basically ripped off from remove_sub_domain_data, modularized
sub _remove_generic {
    my ( $input, $field, @suffixes_to_unlink ) = @_;
    my $field_singular = $field;
    $field_singular =~ s/s$//g;

    if ( !$input->{'user'} || !$input->{$field_singular} ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( 'Invalid arguments', 'warn', __PACKAGE__, 1 );
        return;
    }
    {
        my $guard = Cpanel::Config::userdata::Guard->new( $input->{'user'}, 'main' );
        my $main  = $guard->data();
        $main->{$field} = [ Cpanel::ArrayFunc::Uniq::uniq( grep { $input->{$field_singular} ne $_ } @{ $main->{$field} } ) ];

        # Remove files when we still have the lock to prevent
        # a race condition where we think the domain still exists
        _remove_files( $input->{'user'}, ( map { "$input->{$field_singular}$_" } @suffixes_to_unlink ) );

        $guard->save();
    }

    unless (@suffixes_to_unlink) {
        update_cache( $input->{'user'} ) unless $input->{'no_cache_update'};
        return 1;
    }

    update_cache( $input->{'user'} ) unless $input->{'no_cache_update'};

    return 1;
}

sub _remove_files {
    my ( $user, @suffixes ) = @_;
    return unlink map { "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/$_" } @suffixes;
}

1;

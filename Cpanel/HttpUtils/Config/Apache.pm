package Cpanel::HttpUtils::Config::Apache;

# cpanel - Cpanel/HttpUtils/Config/Apache.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache                      ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::ApacheConf                   ();
use Cpanel::ApacheConf::Parser::Regex    ();
use Cpanel::Config::Httpd::IpPort        ();
use Cpanel::Destruct                     ();
use Cpanel::Hostname                     ();
use Cpanel::Config::Httpd::EA4           ();
use Cpanel::HttpUtils::Vhosts::Primary   ();
use Cpanel::HttpUtils::Vhosts::Regex     ();
use Cpanel::IP::Parse                    ();
use Cpanel::LoadModule                   ();
use Cpanel::Debug                        ();
use Cpanel::Signal::Defer                ();
use Cpanel::StringFunc::Trim             ();
use Cpanel::Transaction                  ();
use Cpanel::Validate::IP                 ();
use Cpanel::Validate::IP::v4             ();
use Cpanel::WildcardDomain               ();
use Cpanel::WildcardDomain::Tiny         ();
use Cpanel::XSLib                        ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::userdata::Load       ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

use constant MAX_EXPECTED_VHOST_SIZE => 8192;

our $ACTIVE_OBJECT;

my $PACKAGE = __PACKAGE__;

my $vhost_content_capture_regex;
my $vhost_ip_capture_regex;
my $vhost_servername_capture_regex;

my $_migrate_ip_method_name_duplicate_ips_in_map = 'duplicate_in_map';
my $_migrate_ip_method_name_remove_ips_in_map    = 'remove_ips_in_map';

my $NAME_VIRTUAL_HOST_DIRECTIVE = 'NameVirtualHost';

my $std_port;
my $ssl_port;

# Constants
my $NO_SSL = 0;
my $IS_SSL = 1;

#reduced to 50 to support ipv6
my $IPS_PER_PROXY_SUBDOMAINS_VHOST = 50;

#These are used below.
my %primary_vhost_obj_getter = (
    1 => 'get_primary_ssl_servername',
    0 => 'get_primary_non_ssl_servername',
);
my %primary_vhost_obj_setter = (
    1 => 'set_primary_ssl_servername',
    0 => 'set_primary_non_ssl_servername',
);
my %primary_vhost_obj_unsetter = (
    1 => 'unset_primary_ssl_servername',
    0 => 'unset_primary_non_ssl_servername',
);

my $locale;

sub new {
    my ( $class, $opts ) = @_;

    my ( $ok, $res ) = Cpanel::Transaction::get_httpd_conf();
    die $res if !$ok;

    my $self = bless { _transaction_obj => $res }, $class;

    # Dies on failure
    $self->{'_primary_vhosts_obj'} = Cpanel::HttpUtils::Vhosts::Primary->new();

    # Dies on failure
    $self->{'_apache_conf_obj'} = Cpanel::ApacheConf->new( httpd_conf_transaction => $res );

    $self->{'_domains_with_ssl_resources_to_cleanup'} = [];

    $self->{'_verify_syntax'} = ( $opts && $opts->{'verify_syntax'} ) ? 1 : 0;

    $ACTIVE_OBJECT = $self;

    return $self;
}

sub DESTROY {
    my $self = shift;

    return if !$ACTIVE_OBJECT;
    return if Cpanel::Destruct::in_dangerous_global_destruction();

    my ( $ok, $err ) = $self->close();
    warn $err if !$ok;

    return;
}

#save() can be called multiple times; an exception will result if you
#try to do a save() after an abort() or close().
sub save {
    my ($self) = @_;

    if ( $self->{'_needs_proxy_subdomains_update'} ) {
        $self->_update_proxy_subdomains();
        $self->{'_needs_proxy_subdomains_update'} = 0;
    }

    # We used to check httpd.conf syntax when we installed ssl certificates
    # in case there was a problem with them.  This is no longer done
    # since we pass all certificates through Cpanel::SSL::Verify to make
    # sure apache is not going to choke on them.
    #
    # TL;DR: Cpanel::SSLInstall::_validate_ssl_components does this much faster and
    # gives us better errors
    #
    if ( $self->{'_verify_syntax'} ) {
        my $httpdconf_text_sr = $self->_get_httpd_conf_transaction_obj()->get_data();

        require Cpanel::ConfigFiles::Apache::Syntax;
        my $ref = Cpanel::ConfigFiles::Apache::Syntax::find_httpd_conf_errors($httpdconf_text_sr);
        return ( 0, $ref->{'message'} ) if !$ref->{'status'};

        my @check_errs = split( /\n/, $ref->{'message'} );
        if (@check_errs) {
            s/(line[ \t]+\d+[ \t]+of[ \t]+)[^:]+/$1\[Test Configuration File\]/ for @check_errs;
            return ( 0, join( "\n", @check_errs ) );
        }
    }

    $self->{'_defer'} ||= Cpanel::Signal::Defer->new(
        defer => {
            signals => Cpanel::Signal::Defer::NORMALLY_DEFERRED_SIGNALS(),
        }
    );

    my ( $ok, $msg ) = $self->{'_transaction_obj'}->save();
    if ( !$ok ) {
        Cpanel::Debug::log_warn("There was an error saving the Apache configuration as part of a transaction: $msg");

        my ( $ok, $err ) = $self->abort();
        $msg .= "\n$err" if !$ok;

        $self->_reset_deferred_signals();
        return ( 0, $msg );
    }

    ( $ok, $msg ) = $self->{'_primary_vhosts_obj'}->save();
    if ( !$ok ) {
        Cpanel::Debug::log_warn("There was an error saving the primary VirtualHost configuration as part of a transaction: $msg");

        my ( $ok, $err ) = $self->abort();
        $msg .= "\n$err" if !$ok;

        $self->_reset_deferred_signals();
        return ( 0, $msg );
    }

    #Cpanel::ApacheConf->destroy currently eats failures, so we can't check
    #for that here.
    #'$Cpanel::ApacheConf::MEMORY_CACHE_IS_IN_SYNC' means don't stat httpd.conf because we know the datastore is in sync with it.
    #'$Cpanel::ApacheConf::FORCE_WRITE_DATASTORE' is always set because we just wrote httpd.conf and we need to make sure
    #the datastore is written to disk so we do not have to build it next time we load httpd.conf since the mtime would be older
    #and force a rebuild
    $self->{'_apache_conf_obj'}->destroy( $Cpanel::ApacheConf::MEMORY_CACHE_IS_IN_SYNC, $Cpanel::ApacheConf::FORCE_WRITE_DATASTORE );

    # Here we want to clean up the queued domains as we wanted to avoid a situtation where the Apache configuration
    # didn't save properly and there were still references to the resources we were removing.
    if ( @{ $self->{'_domains_with_ssl_resources_to_cleanup'} } ) {
        ( $ok, $msg ) = $self->_cleanup_enqueued_remove_from_sslstorage_and_userdata_and_ssldomains();
        if ( !$ok ) {
            my $combined_messages = ref $msg ? join( ', ', @$msg ) : $msg;
            Cpanel::Debug::log_warn("There were errors removing SSL resources for deleted domains: $combined_messages");

            my ( $ok, $err ) = $self->close();
            $msg .= "\n$err" if !$ok;

            $self->_reset_deferred_signals();
            return ( 0, $msg );
        }
    }

    $self->_reset_deferred_signals();

    return 1;
}

# Close will end a transaction. Calls to save after close() or abort() will fail.
# Close should be called if all saves have been completed and we need to clean up locks.
sub close {
    my ($self) = @_;

    my @messages = ();
    if ( $self->{'_primary_vhosts_obj'} ) {
        my ( $ok, $msg ) = $self->{'_primary_vhosts_obj'}->close();
        push @messages, $msg if !$ok;
    }

    if ( $self->{'_apache_conf_obj'} ) {

        # Cpanel::ApacheConfig->destroy currently eats failures
        #'1' means don't stat httpd.conf because we know the datastore is in sync with it.
        $self->{'_apache_conf_obj'}->destroy(1);
    }

    if ( $self->{'_transaction_obj'} ) {
        my ( $ok, $msg ) = $self->{'_transaction_obj'}->close();
        push @messages, $msg if !$ok;
    }

    $ACTIVE_OBJECT = undef;

    return scalar @messages ? ( 0, \@messages ) : 1;
}

#abort() can be called multiple times; additional calls to abort()
#just won't do anything useful. Calls to save after abort() or close() will fail.
# abort should be called if objects were modified but not all saves have occurred.
sub abort {
    my ($self) = @_;

    my @messages = ();
    if ( $self->{'_primary_vhosts_obj'} ) {
        my ( $ok, $msg ) = $self->{'_primary_vhosts_obj'}->abort();
        push @messages, $msg if !$ok;
    }

    if ( $self->{'_apache_conf_obj'} ) {
        $self->{'_apache_conf_obj'}->clear_memory_cache();

        # Cpanel::ApacheConfig->destroy currently eats failures
        #'1' means don't stat httpd.conf because we know the datastore is in sync with it.
        $self->{'_apache_conf_obj'}->destroy(1);
    }

    if ( $self->{'_transaction_obj'} ) {
        my ( $ok, $msg ) = $self->{'_transaction_obj'}->abort();
        push @messages, $msg if !$ok;
    }

    $ACTIVE_OBJECT = undef;

    return scalar @messages ? ( 0, \@messages ) : 1;
}

sub add_vhost {
    my ( $self, $vhost_entry ) = @_;

    return $self->_do_add($vhost_entry);
}

# This method is used in the first stage of an IP migration by adding the new IP address passed in via the map along side
# the IP address being migrated away from/replaced.
# Expects an IP map in the form of:
# { $oldip => $newip, $oldip2 => $newip2 } Where $oldip is the ip migrating away from and $newip is the ip migrating to.
sub migrate_ip_duplicate_ips_in_map {
    my ( $self, %OPTS ) = @_;

    return $self->_do_migrate_ips( 'method' => $_migrate_ip_method_name_duplicate_ips_in_map, %OPTS );
}

# This method is used in the final stage of an IP migration by removing the old IP addresses passed in via the map from the
# apache virtualhosts. This will leave the new ip address on the virtualhosts.
# Expects an IP map in the form of:
# { $oldip => $newip, $oldip2 => $newip2 } Where $oldip is the ip migrating away from and $newip is the ip migrating to.
sub migrate_ip_remove_ips_in_map {
    my ( $self, %OPTS ) = @_;

    return $self->_do_migrate_ips( 'method' => $_migrate_ip_method_name_remove_ips_in_map, %OPTS );
}

#This figures out SSL/non-SSL from the $new_entry.
#This is NOT for changing a vhost's IP; use change_ip() for that.
#
#This assumes that $new_entry is correctly formatted!
sub replace_vhosts_by_name {
    my ( $self, $servername, $new_entry ) = @_;

    $new_entry =~ Cpanel::ApacheConf::Parser::Regex::VirtualHost_ServerName_Capture();
    my $new_servername = Cpanel::WildcardDomain::decode_wildcard_domain("$1");

    if ( !$new_servername ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext( 'The VirtualHost is invalid. It does not contain the “[_1]” directive.', 'ServerName' )
          : 'The VirtualHost is invalid. It does not contain the “ServerName” directive.';
        return ( 0, $msg );
    }

    $new_entry =~ Cpanel::HttpUtils::Vhosts::Regex::VirtualHost_IP_Capture();
    my $ips_str = $1;
    my ($first_ip) = ( $ips_str =~ m{\A\s*(\S+)} );
    my ( undef, $ip, $port ) = Cpanel::IP::Parse::parse( $first_ip, undef, $Cpanel::IP::Parse::BRACKET_IPV6 );
    if ( !$ip || !$port ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext('The VirtualHost is invalid. It does not contain an IP address or port.')
          : 'The VirtualHost is invalid. It does not contain an IP address or port.';
        return ( 0, $msg );
    }

    #Make sure we're not trying to change IPs here.
    my $domains_ar = $self->fetch_domains_on_ip_port( $ip, $port );
    if ( -1 == Cpanel::XSLib::get_array_index_eq( $domains_ar, $servername ) ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext( 'The ServerName “[_1]” is not on the “[_2]:[_3]” binding.', $servername, $ip, $port )
          : "The ServerName “$servername” is not on the “$ip:$port” binding.";

        return ( 0, $msg );
    }

    $ssl_port ||= Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();
    my $is_ssl = ( $port eq $ssl_port ) ? 1 : 0;

    my $primary_getter_name      = $primary_vhost_obj_getter{$is_ssl};
    my $primary_servername_on_ip = $self->_get_primary_vhosts_obj()->$primary_getter_name($ip);

    my $type = $is_ssl ? 'ssl' : 'std';

    my ( $remove_ok, $removed ) = $self->_do_remove_by_servername_with_datastore( $servername, $type );
    return ( 0, $removed ) if !$remove_ok;

    my ( $add_ok, $add_msg ) = $self->add_vhost($new_entry);
    return ( 0, $add_msg ) if !$add_ok;

    #If we are replacing a vhost with another vhost with the same servername,
    #AND if the vhost was the IP address's primary vhost on that port,
    #then we need to move the new vhost back to being primary.

    if (
           defined $primary_servername_on_ip
        && $primary_servername_on_ip eq $servername
        && !Cpanel::WildcardDomain::Tiny::is_wildcard_domain($servername)    # Its possible that the wildcard domain is the only
                                                                             # domain for SSL so it is the "implicit primary"
                                                                             # in this case we do not want to move it
                                                                             # since its a wildcard and already in the
                                                                             # correct place.  Attempting to set it as
                                                                             # the primary will cause an error since
                                                                             # wildcard may not be "explicit primary"
    ) {
        if ( $new_servername eq $servername ) {

            #Use the full set_primary_servername here because
            #remove_vhosts_by_name() above may have altered the primary entry.
            my ( $set_ok, $set_msg ) = $self->set_primary_servername( $servername, $type );
            return ( 0, $set_msg ) if !$set_ok;
        }
        else {
            my $first_on_ip_port = $self->_get_apache_conf_datastore_obj()->find_first_servername_on_ip_port( $ip, $port );

            my $primary_setter_name = $primary_vhost_obj_setter{$is_ssl};
            $self->_get_primary_vhosts_obj()->$primary_setter_name( $ip, $port, $first_on_ip_port );
        }
    }

    return ( 1, $removed );
}

#Public method that removes the vhosts and associated userdata and SSLStorage.
#Do NOT call this method if the vhost isn't *actually* being removed; e.g., if your
#transaction will remove, alter, then re-add the vhost.
sub remove_vhosts_by_name {
    my ( $self, $servername, $type ) = @_;

    my ( $ok, $removed ) = $self->_do_remove_by_servername_with_datastore( $servername, $type );
    if ( $type && $type eq 'ssl' && $ok && $removed ) {
        $self->_enqueue_remove_from_sslstorage_and_userdata_and_ssldomains( $removed->{'servername'} );
    }

    return ( $ok, [ $removed || () ] );
}

#Public: see comment about remove_vhosts_by_name.
## This used to take a $type of 'std' or 'ssl'
##  however it was never used and all vhosts
##  were removed reguardless.  Since this is what
##  all callers wanted the $type param was removed.
sub remove_vhosts_by_user {
    my ( $self, $username ) = @_;

    my ( $ok, $removed ) = $self->_remove_vhosts_by_user($username);
    if ( $ok && $removed ) {
        for my $removed_entry (@$removed) {
            $self->_enqueue_remove_from_sslstorage_and_userdata_and_ssldomains( $removed_entry->{'servername'} );
        }
    }

    return ( $ok, $removed );
}

#Private: see comment about _remove_vhosts_by_name.
sub _remove_vhosts_by_user {
    my ( $self, $username ) = @_;

    my $homedir = Cpanel::PwCache::gethomedir($username);
    $homedir =~ s{/+\z}{} if defined $homedir;

    if ( !$homedir ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext( 'The system could not determine a home directory for the user “[_1]”.', $username )
          : "The system could not determine a home directory for the user “$username”.";
        return ( 0, $msg );
    }

    my $servername_ports_ar = $self->_get_apache_conf_datastore_obj()->find_homedir_servername_ports($homedir);

    my %port_type = map { $self->_get_port_by_type($_) => $_ } qw(std ssl);

    my @all_removed;

    for my $servername_port (@$servername_ports_ar) {
        my ( $servername, $port )    = @$servername_port;
        my ( $ok,         $removed ) = $self->_do_remove_by_servername_with_datastore( $servername, $port_type{$port} );
        if ($ok) {
            push @all_removed, $removed if $removed;    # _do_remove_by_servername_with_datastore() can succeed without returning a removed item
        }
    }

    remove_vhost_include_directory($username);

    return 1, \@all_removed;
}

sub remove_vhost_include_directory {
    my ($user)          = @_;
    my @apache_versions = ( 1,     2 );
    my @types           = ( 'ssl', 'std' );

    my $confdir = apache_paths_facade->dir_conf_userdata();

    require Cpanel::SafeDir::RM;

    foreach my $type (@types) {
        next if ( !-d "$confdir/$type" );
        foreach my $version (@apache_versions) {
            next if ( !-d "$confdir/$type/$version/" );
            my $include_dir = "$confdir/$type/$version/$user";
            if ( -d $include_dir ) {
                Cpanel::SafeDir::RM::safermdir($include_dir);
            }
        }

    }
    return;
}

sub _get_port_by_type {
    my ( $self, $type ) = @_;

    if ( $type eq 'ssl' ) {
        return Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();
    }

    return Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
}

sub _do_remove_by_servername_with_datastore {
    my ( $self, $servername, $type ) = @_;

    my $is_ssl;

    ( $is_ssl, $type ) = eval { _normalize_is_ssl($type) };
    return ( 0, $@ ) if !defined $is_ssl;

    my $port          = $self->_get_port_by_type($type);
    my $http_conf_obj = $self->_get_apache_conf_datastore_obj();
    my $vhost_offset  = $http_conf_obj->find_vhost_offset_by_servername_port( $servername, $port );

    return ( 1, () ) if !defined $vhost_offset;

    my $httpd_conf_transaction = $self->_get_httpd_conf_transaction_obj();
    my $httpdconf_text_sr      = $httpd_conf_transaction->get_data();

    # First try looking ahead to see if we can just match a small portion of
    # the httpd.conf as its much faster than matching the whole string.

    my $lookahead_text;
    my $MIN_EXPECTED_VHOST_SIZE = 15;    # at minimum we want </virtualhost>
    if ( ( length($$httpdconf_text_sr) - $vhost_offset ) >= $MIN_EXPECTED_VHOST_SIZE ) {
        $lookahead_text = substr( $$httpdconf_text_sr, $vhost_offset, MAX_EXPECTED_VHOST_SIZE );
    }

    my $vhost_end;
    my $found_end = ( defined $lookahead_text && $lookahead_text =~ m{\n\s*</virtualhost>}gis );
    if ($found_end) {
        $vhost_end = $vhost_offset + $+[0];
    }
    else {
        # In this case we didn't find the end of the vhost with our lookahead
        # so we do a longer search of the whole httpd.conf

        pos($$httpdconf_text_sr) = $vhost_offset;
        $found_end = ( $$httpdconf_text_sr =~ m{\n\s*</virtualhost>}gis );
        $vhost_end = int $+[0];
        if ( !$found_end ) {
            warn "corrupt httpd.conf, removing $servername, $type, offset $vhost_offset\n$$httpdconf_text_sr";
        }
    }

    # It’s now important that we remove_record() prior to updating
    # the httpd.conf buffer because the latter operation will also
    # do $http_conf_obj->update_vhost_offsets(), which, if remove_record()
    # isn’t yet called, will produce an error because we’re trying to
    # record a negative offset in httpd.conf for a vhost.
    #
    my $removed = $http_conf_obj->remove_record( $servername, $port );
    my $ip      = $removed->{'ip'};

    my $vhost_entry = $self->_httpd_conf_substr(
        $vhost_offset,
        $vhost_end - $vhost_offset,
        q{},
    );

    my $primary_vhosts_obj = $self->_get_primary_vhosts_obj();

    #Identify a new primary vhost for the IP if necessary.
    #This is a bit backwards from "normal"; ideally, we determine
    #httpd.conf from primary_vhosts, not the other way around.
    my $getter_name              = $primary_vhost_obj_getter{$is_ssl};
    my $primary_servername_on_ip = $primary_vhosts_obj->$getter_name($ip);
    my $setter                   = $primary_vhost_obj_setter{$is_ssl};
    my $unsetter_name            = $primary_vhost_obj_unsetter{$is_ssl};

    my $new_primary_servername_on_ip;
    if ( $primary_servername_on_ip && ( $primary_servername_on_ip eq $servername ) ) {
        $new_primary_servername_on_ip = $http_conf_obj->find_first_servername_on_ip_port( $ip, $port );

        #Our httpd.conf has "default" vhosts that are the actual first vhosts for IP/port.
        #Ensure that we don't inadvertently set one of those in the primary vhosts datastore.
        #
        my $servername_is_ip = 0;
        if ( defined $new_primary_servername_on_ip ) {
            $servername_is_ip = Cpanel::Validate::IP::v4::is_valid_ipv4($new_primary_servername_on_ip);
            $servername_is_ip ||= Cpanel::Validate::IP::is_valid_ipv6($new_primary_servername_on_ip);
        }

        if ( $new_primary_servername_on_ip && !$servername_is_ip ) {

            if ($is_ssl) {

                # We need to check that the new primary ssl vhost has an SSL userdata file.
                my $domain_owner_hr = (
                    $Cpanel::AcctUtils::DomainOwner::Tiny::CACHE_IS_SET
                    ? Cpanel::AcctUtils::DomainOwner::Tiny::get_cache()
                    : Cpanel::AcctUtils::DomainOwner::Tiny::build_domain_cache()
                );

                # If there is no owner, we need to check under the nobody user.
                my $owner = $domain_owner_hr->{$new_primary_servername_on_ip} || 'nobody';

                if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $owner, $new_primary_servername_on_ip ) ) {
                    $primary_vhosts_obj->$setter( $ip, $new_primary_servername_on_ip );
                }
                else {
                    $primary_vhosts_obj->$unsetter_name($ip);
                }
            }
            else {
                $primary_vhosts_obj->$setter( $ip, $new_primary_servername_on_ip );
            }

        }
        else {
            $primary_vhosts_obj->$unsetter_name($ip);
        }
    }
    else {
        $new_primary_servername_on_ip = $primary_servername_on_ip;
    }

    # If all virtualhosts on the ip have been removed
    # we need to update the service (formerly proxy) subdomains
    if ( !$new_primary_servername_on_ip ) {
        $self->{'_needs_proxy_subdomains_update'} = 1;
    }

    return 1,
      {
        primary_on_ip_port => $new_primary_servername_on_ip,
        ip_port            => [ $ip, $port ],
        is_ssl             => $is_ssl,
        servername         => $servername,
        vhost_entry        => $vhost_entry,
      };
}

sub _do_add {
    my ( $self, $vhost_entry ) = @_;

    my $http_conf_obj      = $self->_get_apache_conf_datastore_obj();
    my $primary_vhosts_obj = $self->_get_primary_vhosts_obj();

    my $httpd_conf_transaction = $self->_get_httpd_conf_transaction_obj();
    my $httpdconf_text_sr      = $httpd_conf_transaction->get_data();

    $ssl_port ||= Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();
    $std_port ||= Cpanel::Config::Httpd::IpPort::get_main_httpd_port();

    my $servername = get_vhost_servername($vhost_entry);
    my $ips_ports  = get_vhost_ips_ports($vhost_entry);
    for my $ip_port (@$ips_ports) {
        my $port   = ( $ip_port->[1] && $ip_port->[1] eq $ssl_port ) ? $ssl_port : $std_port;
        my $is_ssl = $port eq $ssl_port                              ? 1         : 0;
        my $new_ip = $ip_port->[0];

        # IPv6 addresses do not go into the primary vhosts file
        next if ( Cpanel::Validate::IP::is_valid_ipv6($new_ip) );

        my $get_method               = $is_ssl ? 'get_primary_ssl_servername' : 'get_primary_non_ssl_servername';
        my $primary_servername_on_ip = $primary_vhosts_obj->$get_method($new_ip);

        if ( !$primary_servername_on_ip ) {

            # We only need to update service (formerly proxy) subdomains
            # if we have added a new ip
            $self->{'_needs_proxy_subdomains_update'} = 1;
        }

        #Set the new vhost as primary if:
        #   - There is no primary, OR
        #   - The existing primary is a wildcard, and the new one isn't.
        my $make_the_new_one_primary = !$primary_servername_on_ip || ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($primary_servername_on_ip) && !Cpanel::WildcardDomain::Tiny::is_wildcard_domain($servername) );

        if ($make_the_new_one_primary) {
            my $set_method = $is_ssl ? 'set_primary_ssl_servername' : 'set_primary_non_ssl_servername';
            $primary_vhosts_obj->$set_method( $new_ip, $servername );
        }
    }

    my $add_text_result = $self->_add_vhost_text(
        httpdconf_text => $httpdconf_text_sr,
        entry          => $vhost_entry,
    );

    $http_conf_obj->add_record($vhost_entry);

    for my $ip_port (@$ips_ports) {
        $http_conf_obj->set_vhost_offset( $servername, $ip_port->[1], $add_text_result->{'added_entry'}{'vhost_start_position'} );
    }

    my $added_vhost_entry = $add_text_result->{'added_entry'}{'vhost_entry'};

    #Delete this since it exposes an implementation detail.
    delete $add_text_result->{'added_entry'}{'vhost_entry'};

    # TODO: syntax check || revert && return;
    return ( 1, $add_text_result->{'added_entry'} );
}

sub _httpd_conf_substr {
    my ( $self, @substr_args ) = @_;

    my $ret = $self->_get_httpd_conf_transaction_obj()->substr(@substr_args);

    if ( scalar @substr_args > 2 ) {
        my ( $offset, $replacee_length, $replacement ) = @substr_args;
        my $growth = length($replacement) - $replacee_length;

        $self->_get_apache_conf_datastore_obj()->update_vhost_offsets( $offset, $growth );
    }

    return $ret;
}

sub change_vhost_ip {
    my ( $self, $servername, $new_ip, $type ) = @_;

    my $is_ssl;
    ( $is_ssl, $type ) = eval { _normalize_is_ssl($type) };
    return ( 0, $@ ) if !defined $is_ssl;

    my $port = $is_ssl ? Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port() : Cpanel::Config::Httpd::IpPort::get_main_httpd_port();

    my $http_conf_obj = $self->_get_apache_conf_datastore_obj()->{'data'};
    my $address_ar    = $http_conf_obj->{$servername} && $http_conf_obj->{$servername}{'address'};

    my $old_ip;
    if ($address_ar) {
        for my $addr_entry (@$address_ar) {
            if ( $addr_entry->{'port'} eq $port ) {
                $old_ip = $addr_entry->{'ip'};
                last;
            }
        }
    }
    if ( !$old_ip ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext( 'The ServerName “[_1]” is not installed as “[_2]”.', $servername, $type )
          : "The ServerName “$servername” is not installed as “$type”.";
        return ( 0, $msg );
    }

    my ( $ok, $removed ) = $self->_do_remove_by_servername_with_datastore( $servername, $type );
    return ( 0, $removed ) if !$ok;

    my $new_entry = $removed->{'vhost_entry'} // '';
    $new_entry =~ s{\n\s*(<virtualhost.*[^0-9])\Q$old_ip\E:}{$1$new_ip:}is;

    my ( $add_ok, $add_msg ) = $self->add_vhost($new_entry);
    return ( 0, $add_msg ) if !$add_ok;

    # We need to ensure that the service subdomains vhost
    # is updated to listen on the new IP for the site
    $self->{'_needs_proxy_subdomains_update'} = 1;

    return 1;
}

sub get_primary_servername {
    my ( $self, $ip, $type ) = @_;

    my $is_ssl;
    ( $is_ssl, $type ) = eval { _normalize_is_ssl($type) };
    return ( 0, $@ ) if !defined $is_ssl;

    my $getter_name = $primary_vhost_obj_getter{$is_ssl};

    return $self->_get_primary_vhosts_obj()->$getter_name($ip);
}

#This is for rearranging vhosts that are already installed.
sub set_primary_servername {
    my ( $self, $servername, $type ) = @_;

    my $is_ssl;
    ( $is_ssl, $type ) = eval { _normalize_is_ssl($type) };
    return ( 0, $@ ) if !defined $is_ssl;

    if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($servername) ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext('A website for a wildcard domain cannot be set as the primary website on an IP address.')
          : 'A website for a wildcard domain cannot be set as the primary website on an IP address.';
        return ( 0, $msg );
    }

    my $http_conf_obj   = $self->_get_apache_conf_datastore_obj();
    my $datastore_entry = $http_conf_obj->{'data'}{$servername};

    #Implementor error - we shouldn't have gotten this far.
    if ( !$datastore_entry ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext( 'The ServerName “[_1]” is not installed.', $servername )
          : "The ServerName “$servername” is not installed.";
        return ( 0, $msg );
    }

    if ( !$datastore_entry->{'address'} ) {
        $locale ||= _load_locale();
        my $warning = "The ServerName “$servername” is missing the “address” entry in the datastore.";
        Cpanel::Debug::log_warn($warning);
        my $msg =
            $locale
          ? $locale->maketext( 'The ServerName “[_1]” is missing the “[_2]” entry in the datastore.', $servername, 'address' )
          : $warning;
        return ( 0, $msg );
    }

    my $port = $is_ssl ? Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port() : Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    my $ip;
    for my $ip_port ( @{ $datastore_entry->{'address'} } ) {
        if ( $ip_port->{'port'} == $port ) {
            $ip = $ip_port->{'ip'};
            last;
        }
    }

    my $primary_obj                  = $self->_get_primary_vhosts_obj();
    my $getter_name                  = $primary_vhost_obj_getter{$is_ssl};
    my $old_primary_servername_on_ip = $primary_obj->$getter_name($ip);

    return 1 if length($old_primary_servername_on_ip) && $old_primary_servername_on_ip eq $servername;    #Nothing to do!

    my ( $set_ok, $set_msg ) = $self->_reorder_vhost_to_be_primary_in_httpd_conf( $servername, $ip, $port );
    return ( 0, $set_msg ) if !$set_ok;

    my $setter_name = $primary_vhost_obj_setter{$is_ssl};
    $primary_obj->$setter_name( $ip, $servername );

    return 1;
}

sub fetch_domains_on_ip_port {
    my ( $self, $ip, $port ) = @_;

    return $self->_get_apache_conf_datastore_obj()->fetch_domains_on_ip_port( $ip, $port );
}

sub servername_type_is_active {
    my ( $self, $servername, $type ) = @_;

    $type ||= 'std';

    my $port;
    if ( $type eq 'ssl' ) {
        $port = $ssl_port ||= Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();
    }
    elsif ( $type eq 'std' ) {
        $port = $std_port ||= Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    }
    else {    #Programmer error
        die "Invalid vhost type: $type (use 'std' or 'ssl')";
    }

    return defined $self->_get_apache_conf_datastore_obj()->find_vhost_offset_by_servername_port( $servername, $port ) ? 1 : 0;
}

#Returns crt, key, cab
sub _extract_vhost_ssl_paths {
    my ($vhost) = @_;

    my ($crt) = ( $vhost =~ m{\n[ \t]*sslcertificatefile[ \t]+(\S[^\n]+\S)}i );
    my ($key) = ( $vhost =~ m{\n[ \t]*sslcertificatekeyfile[ \t]+(\S[^\n]+\S)}i );
    my ($cab) = ( $vhost =~ m{\n[ \t]*sslcacertificatefile[ \t]+(\S[^\n]+\S)}i );

    return ( $crt, $key, $cab );
}

#Call this after an SSL vhost has been removed from httpd.conf.
#This is for when an SSL vhost has *really* been removed, not just
#when it's being altered.
sub _enqueue_remove_from_sslstorage_and_userdata_and_ssldomains {
    my ( $self, $domain ) = @_;

    if ( !$domain ) {
        Cpanel::Debug::log_warn("_enqueue_remove_from_sslstorage_and_userdata_and_ssldomains requires a domain");
        return;
    }

    push @{ $self->{'_domains_with_ssl_resources_to_cleanup'} }, $domain;

    return 1;
}

#NB: tested directly
sub _cleanup_enqueued_remove_from_sslstorage_and_userdata_and_ssldomains {
    my ($self) = @_;

    # Loadmodule already logs failures to load
    Cpanel::LoadModule::loadmodule('AcctUtils::DomainOwner::Tiny') or return ( 0, $@ );
    Cpanel::LoadModule::loadmodule('Config::userdata')             or return ( 0, $@ );

    require Cpanel::Apache::TLS::Write;

    my $apache_tls = Cpanel::Apache::TLS::Write->new();

    my @messages = ();

    for my $domain ( @{ $self->{'_domains_with_ssl_resources_to_cleanup'} } ) {
        my $owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => 'nobody', 'skiptruelookup' => 1 } );    # nobody is the default owner
        if ($owner) {
            if ( ( $owner eq 'nobody' || $owner eq 'root' ) && $domain ne Cpanel::Hostname::gethostname() ) {

                #
                # Since nobody can only have SSL domains installed we want to remove
                # all references about the domain from userdata.  The exception
                # is the main hostname, since we don't want to blow away the
                # main userdata there.
                #
                Cpanel::Config::userdata::remove_domain_data( { 'user' => 'nobody', 'domain' => $domain } );
            }
            else {
                Cpanel::Config::userdata::remove_user_domain_ssl( $owner, $domain );
            }
        }

        if ( $apache_tls->has_tls($domain) ) {
            $apache_tls->enqueue_unset_tls($domain);
        }
    }

    $self->{'_domains_with_ssl_resources_to_cleanup'} = [];

    return scalar @messages ? ( 0, \@messages ) : 1;
}

sub _do_migrate_ips {
    my ( $self, %OPTS ) = @_;

    my $ipmap  = $OPTS{'ipmap'};
    my $method = $OPTS{'method'} || $_migrate_ip_method_name_duplicate_ips_in_map;    # by default we take the ips in the
                                                                                      # ipmap hash and add the values to places where the keys are used

    if ( $method ne $_migrate_ip_method_name_duplicate_ips_in_map && $method ne $_migrate_ip_method_name_remove_ips_in_map ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext( 'The method “[_1]” is not supported.', $method )
          : "The method “$method” is not supported.";
        return ( 0, $msg );
    }
    elsif ( !ref $ipmap || !scalar keys %{$ipmap} ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext( 'The parameter “[_1]” is required and must be a non-empty hashref.', 'ipmap' )
          : "The parameter “$ipmap” is required and must be a non-empty hashref.";
        return ( 0, $msg );
    }

    my $httpd_datastore        = $self->_get_apache_conf_datastore_obj();
    my $primary_vhosts_obj     = $self->_get_primary_vhosts_obj();
    my $httpd_conf_transaction = $self->_get_httpd_conf_transaction_obj();

    my $httpd_conf_sr = $httpd_conf_transaction->get_data();

    my $has_proxy_vhosts = 0;

    my %seen_namevirtualhosts;
    my ( $line, $line_offset );

    while ( $$httpd_conf_sr =~ m{([^\n]*\n)}g ) {
        ( $line, $line_offset ) = ( $1, $-[0] );

        my $replacement_line;
        if ( !$has_proxy_vhosts && $line =~ m/^\s*# CPANEL\/WHM\/WEBMAIL(\/WEBDISK)?(?:\/AUTOCONFIG)? PROXY SUBDOMAINS/ ) {
            $has_proxy_vhosts = 1;
        }
        elsif ( $line =~ m/^\s*NameVirtualHost\s+/i ) {
            my $vhostline = $line;
            $vhostline =~ s/^\s+//;
            $vhostline =~ s/[\s\n]+$//;
            my ($currentip) = ( split( /\s+/, $vhostline ) )[1];
            my ( $version, $port );
            ( $version, $currentip, $port ) = Cpanel::IP::Parse::parse( $currentip, undef, $Cpanel::IP::Parse::BRACKET_IPV6 );

            $replacement_line = q{};
            my $newip = $ipmap->{$currentip};

            #If we've found an IP that needs to be removed, then leave
            #$replacement_line as q{} so that the substr() below will
            #end up removing this line.
            if ( !$newip || $method ne $_migrate_ip_method_name_remove_ips_in_map ) {
                if ($newip) {
                    my $key = "$newip" . ( $port ? ":$port" : '' );
                    $replacement_line .= "$NAME_VIRTUAL_HOST_DIRECTIVE $key\n" unless $seen_namevirtualhosts{$key}++;
                }
                my $key = "$currentip" . ( $port ? ":$port" : '' );
                $replacement_line .= "$NAME_VIRTUAL_HOST_DIRECTIVE $key\n" unless $seen_namevirtualhosts{$key}++;
            }
        }
        elsif ( $line =~ /^\s*ServerName[ \t]/i ) {    # handle the servername being the IP in the case of domain forwarders
            my $servernameline = $line;
            $servernameline =~ s/^\s+//;
            $servernameline =~ s/[>\s\n]+$//;
            my (@servername) = split( /\s+/, $servernameline );
            if ( exists $ipmap->{ $servername[1] } ) {
                $replacement_line = "$servername[0] $ipmap->{$servername[1]}\n";
            }
        }
        elsif ( $line =~ /^\s*<VirtualHost\s+/i ) {
            my $vhostline = $line;
            $vhostline =~ s/^\s+//;
            $vhostline =~ s/[>\s\n]+$//;
            my (@currentips_list) = split( /\s+/, $vhostline );
            shift(@currentips_list);    #remove VirtualHost
            my @newips_list;
            foreach my $ip (@currentips_list) {
                my ( $version, $currentip, $port ) = Cpanel::IP::Parse::parse( $ip, undef, $Cpanel::IP::Parse::BRACKET_IPV6 );
                if ( my $newip = $ipmap->{$currentip} ) {
                    next if $method eq $_migrate_ip_method_name_remove_ips_in_map;
                    push @newips_list, "$newip" . ( $port ? ":$port" : "" );    #order matters for compat
                }
                push @newips_list, "$currentip" . ( $port ? ":$port" : "" );    #order matters for compat
            }
            $replacement_line = "<VirtualHost " . join( ' ', @newips_list ) . ">\n" if @newips_list;
        }

        if ( defined $replacement_line ) {
            $self->_httpd_conf_substr( $line_offset, length($line), $replacement_line );
            pos($$httpd_conf_sr) = $line_offset + length($replacement_line);
        }
    }

    # just rebuild the object at this point since we just changed every vhost
    $httpd_datastore->rebuild();

    if ($has_proxy_vhosts) {
        $self->_force_update_proxy_subdomains();
    }

    if ( $method eq $_migrate_ip_method_name_duplicate_ips_in_map ) {
        $self->_update_primary_vhosts_for_new_ip( $ipmap, $httpd_conf_sr );
    }
    else {
        $self->_update_primary_vhosts_for_ip_removal($ipmap);
    }

    # TODO: syntax check || revert && return;
    return 1;
}

sub _reorder_vhost_to_be_primary_in_httpd_conf {
    my ( $self, $servername, $ip, $port ) = @_;

    my $http_conf_obj = $self->_get_apache_conf_datastore_obj();

    my $vhost_offset = $http_conf_obj->find_vhost_offset_by_servername_port( $servername, $port );
    if ( !defined $vhost_offset ) {
        $locale ||= _load_locale();
        my $msg =
            $locale
          ? $locale->maketext( 'The ServerName “[_1]” is not installed on port “[_2]”.', $servername, $port )
          : "The ServerName “$servername” is not installed on port “$port”.";
        return ( 0, $msg );
    }

    my $found_primary_servername = $http_conf_obj->find_first_servername_on_ip_port( $ip, $port );
    my $found_primary_pos        = $http_conf_obj->find_vhost_offset_by_servername_port( $found_primary_servername, $port );

    if ( !defined $found_primary_pos ) {
        Carp::cluck("httpd.conf is out of sync with primary_virtual_hosts and needs to be regenerated (Could not find position of primary servername).");

        #TODO: Oops! httpd.conf is out of sync with primary_virtual_hosts and needs to be regenerated.
    }
    elsif ( $vhost_offset < $found_primary_pos ) {
        Carp::cluck("httpd.conf is out of sync with primary_virtual_hosts and needs to be regenerated. (The virtual host was unexpectedly before the primary)");

        #TODO: Oops! httpd.conf is out of sync with primary_virtual_hosts and needs to be regenerated.
    }

    my $httpd_conf_transaction = $self->_get_httpd_conf_transaction_obj();
    my $httpdconf_text_sr      = $httpd_conf_transaction->get_data();

    pos($$httpdconf_text_sr) = $vhost_offset;

    my $found_end = ( $$httpdconf_text_sr =~ m{\n\s*</virtualhost>}gi );
    if ( !$found_end ) {
        warn "corrupt httpd.conf, removing $servername, $port, offset $vhost_offset\n$$httpdconf_text_sr";
    }

    my $vhost_end = int $+[0];

    #Remove the servername's vhost.
    my $vhost_entry = $self->_httpd_conf_substr(
        $vhost_offset,
        $vhost_end - $vhost_offset,
        q{},
    );

    #Insert the servername's vhost before its ip's old primary.
    $self->_httpd_conf_substr(
        $found_primary_pos,
        0,
        $vhost_entry,
    );

    $http_conf_obj->set_vhost_offset( $servername, $port, $found_primary_pos );

    return 1;
}

sub _reset_deferred_signals {
    my ($self) = @_;

    if ( $self->{'_defer'} ) {
        my $defer_obj           = delete $self->{'_defer'};
        my $deferred_signals_ar = $defer_obj->get_deferred();
        $defer_obj->restore_original_signal_handlers();

        if ( grep { $_ eq 'ALRM' } @$deferred_signals_ar ) {
            kill 'ALRM', $$;
        }
    }

    return;
}

#
#  Given an ip map, swap the old (keys) primary ips to the new
#  ips (values) in the map
#
sub _update_primary_vhosts_for_new_ip {
    my ( $self, $ipmap, $httpdconf_text_sr ) = @_;

    require Cpanel::HttpUtils::Vhosts::Primary::Extract;
    $ssl_port ||= Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();
    $std_port ||= Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    my $current_primaries = Cpanel::HttpUtils::Vhosts::Primary::Extract::extract_primary_vhosts_from_apache_conf($httpdconf_text_sr);
    my $primary_vhost_obj = $self->_get_primary_vhosts_obj();
    my ( $httpd_primary_servername, $current_primary_servername, $modify_primary_in_apache_conf, $primary_name_to_set, $type );
    for my $newip ( values %$ipmap ) {
        for my $port ( ( $ssl_port, $std_port ) ) {
            $type                       = ( $port eq $ssl_port ) ? 'ssl' : 'std';
            $httpd_primary_servername   = $current_primaries->{"$newip:$port"};
            $current_primary_servername = $self->get_primary_servername( $newip, $type );

            # If primary servername isn't set set it to what we found in httpd.conf
            if ( !$current_primary_servername ) {
                $primary_name_to_set = $httpd_primary_servername;
            }
            elsif ( $httpd_primary_servername ne $current_primary_servername ) {

                # If the set primary servername isn't the same as the httpd.conf entry
                # and if the set primary servername isn't a wildcard domain, make it the primary in httpd.conf again
                if ( !Cpanel::WildcardDomain::Tiny::is_wildcard_domain($current_primary_servername) ) {
                    $modify_primary_in_apache_conf = 1;
                    $primary_name_to_set           = $current_primary_servername;
                }

                # Otherwise, it's already primary in httpd.conf so we just need to
                # set it as the primary in the primary vhost configuration
                else {
                    $primary_name_to_set = $httpd_primary_servername;
                }
            }

            if ($modify_primary_in_apache_conf) {
                my ( $set_ok, $set_msg ) = $self->_reorder_vhost_to_be_primary_in_httpd_conf( $primary_name_to_set, $newip, $port );
                if ( !$set_ok ) {
                    Cpanel::Debug::log_warn("Unable to set '$primary_name_to_set' as primary on '$newip:$port': $set_msg");
                }
                $primary_name_to_set           = undef;
                $modify_primary_in_apache_conf = undef;
            }
            elsif ($primary_name_to_set) {
                if ( $type eq 'ssl' ) {
                    $primary_vhost_obj->set_primary_ssl_servername( $newip, $primary_name_to_set );
                }
                else {
                    $primary_vhost_obj->set_primary_non_ssl_servername( $newip, $primary_name_to_set );
                }
            }
        }
    }

    return;
}

#
#  Given an ip map, remove primary ips that are the old ips (the keys)
#  in the map
#
sub _update_primary_vhosts_for_ip_removal {
    my ( $self, $ipmap ) = @_;

    $ssl_port ||= Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();
    $std_port ||= Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    my $unset_std = $primary_vhost_obj_unsetter{$NO_SSL};
    my $unset_ssl = $primary_vhost_obj_unsetter{$IS_SSL};

    for my $oldip ( keys %$ipmap ) {
        $self->{'_primary_vhosts_obj'}->$unset_std($oldip);
        $self->{'_primary_vhosts_obj'}->$unset_ssl($oldip);
    }

    return;
}

######################################################
# service (formerly proxy) subdomains handling methods

my $proxy_subdomain_vhost_content_regex;

sub _proxy_subdomain_vhost_content_regex {
    if ( !$proxy_subdomain_vhost_content_regex ) {
        my $virtualhost_content_capture_regex = Cpanel::HttpUtils::Vhosts::Regex::VirtualHost_Content_Capture();
        $proxy_subdomain_vhost_content_regex = qr{\n[ \t]*\# CPANEL\/WHM\/WEBMAIL(?:\/WEBDISK)?(?:\/AUTOCONFIG)? PROXY SUBDOMAINS\s*$virtualhost_content_capture_regex};
    }

    return $proxy_subdomain_vhost_content_regex;
}

#Compare the passed-in httpd.conf against the passed-in Cpanel::ApacheConf
#datastore. If there are IPs in the datastore but not in the httpd.conf's
#service (formerly proxy) subdomains section, this will add them.
sub _update_proxy_subdomains {
    my ($self) = @_;

    my $proxy_vhosts_info_hr = $self->_get_proxy_subdomains_data();
    return if !defined $proxy_vhosts_info_hr->{'non_ssl_vhost_start'};    # not enabled

    my ( $reason_to_update_vhost, $ipmap_iplist_ar, $ipmap_ssliplist_ar ) = $self->_proxy_subdomain_ip_check($proxy_vhosts_info_hr);
    return 1 if !( $reason_to_update_vhost and length $reason_to_update_vhost );

    my ( $ok, $msg ) = $self->_force_update_proxy_subdomains(
        iplist_ar            => $ipmap_iplist_ar,
        iplist_ssl_ar        => $ipmap_ssliplist_ar,
        proxy_vhosts_info_hr => $proxy_vhosts_info_hr,
    );

    return ( 1, { reason => $reason_to_update_vhost } );
}

sub _get_proxy_subdomains_data {
    my ($self) = @_;

    my @proxy_vhosts;
    my @proxy_vhosts_ssl;

    my $httpdconf_transaction = $self->_get_httpd_conf_transaction_obj();
    my $httpdconf_text_ref    = $httpdconf_transaction->get_data();
    my $httpd_ssl_port        = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

    my $proxy_subdomains_start = $self->_get_apache_conf_datastore_obj()->get_proxy_subdomains_start();
    pos($$httpdconf_text_ref) = $proxy_subdomains_start || 0;

    my $virtualhost_ip_capture_regex = Cpanel::HttpUtils::Vhosts::Regex::VirtualHost_IP_Capture();
    my $vhost_content_regex          = _proxy_subdomain_vhost_content_regex();

    my ( %ips_in_proxy_vhost, %ips_in_proxy_vhost_ssl );
    while ( $$httpdconf_text_ref =~ m/$vhost_content_regex/g ) {
        my $proxy_vhost = {
            'start'        => $-[0],
            'end'          => $+[0],
            'sample_vhost' => $1 . $2 . $3,
        };
        my $vhost_beginning = $1;
        if ( $vhost_beginning =~ $virtualhost_ip_capture_regex ) {
            my $virtual_host_ips = $1;
            $virtual_host_ips =~ s/\s+$//g;
            foreach my $ip_in_vhost ( split( m/\s+/, $virtual_host_ips ) ) {
                $proxy_vhost->{'ips'}->{$ip_in_vhost} = undef;
            }
        }

        if ( $vhost_beginning =~ m/:$httpd_ssl_port\b/ ) {
            push @proxy_vhosts_ssl, $proxy_vhost;
            @ips_in_proxy_vhost_ssl{ keys %{ $proxy_vhost->{'ips'} } } = ();
        }
        else {
            push @proxy_vhosts, $proxy_vhost;
            @ips_in_proxy_vhost{ keys %{ $proxy_vhost->{'ips'} } } = ();
        }
    }

    # this assumes that the 'non-ssl' virtualhosts for the service (formerly proxy) subdomains
    # and the ssl virtualhosts for the service (formerly proxy) subdomains appear in continuous blocks
    my ( $non_ssl_vhost_start, $non_ssl_vhost_end, $sample_vhost );
    foreach my $non_ssl_proxy_vhost (@proxy_vhosts) {
        $non_ssl_vhost_start = defined $non_ssl_vhost_start ? ( $non_ssl_proxy_vhost->{start} < $non_ssl_vhost_start ? $non_ssl_proxy_vhost->{start} : $non_ssl_vhost_start ) : $non_ssl_proxy_vhost->{start};
        $non_ssl_vhost_end   = defined $non_ssl_vhost_end   ? ( $non_ssl_proxy_vhost->{end} > $non_ssl_vhost_end     ? $non_ssl_proxy_vhost->{end}   : $non_ssl_vhost_end )   : $non_ssl_proxy_vhost->{end};
        $sample_vhost ||= $non_ssl_proxy_vhost->{sample_vhost};
    }

    my ( $ssl_vhost_start, $ssl_vhost_end, $sample_vhost_ssl );
    foreach my $ssl_proxy_vhost (@proxy_vhosts_ssl) {
        $ssl_vhost_start = defined $ssl_vhost_start ? ( $ssl_proxy_vhost->{start} < $ssl_vhost_start ? $ssl_proxy_vhost->{start} : $ssl_vhost_start ) : $ssl_proxy_vhost->{start};
        $ssl_vhost_end   = defined $ssl_vhost_end   ? ( $ssl_proxy_vhost->{end} > $ssl_vhost_end     ? $ssl_proxy_vhost->{end}   : $ssl_vhost_end )   : $ssl_proxy_vhost->{end};
        $sample_vhost_ssl ||= $ssl_proxy_vhost->{sample_vhost};
    }

    return {
        sample_vhost           => $sample_vhost,
        sample_vhost_ssl       => $sample_vhost_ssl,
        ips_in_proxy_vhost     => \%ips_in_proxy_vhost,
        ips_in_proxy_vhost_ssl => \%ips_in_proxy_vhost_ssl,
        non_ssl_vhost_start    => $non_ssl_vhost_start,
        non_ssl_vhost_end      => $non_ssl_vhost_end,
        ssl_vhost_start        => $ssl_vhost_start,
        ssl_vhost_end          => $ssl_vhost_end,
    };
}

sub _force_update_proxy_subdomains {
    my ( $self, %OPTS ) = @_;

    my $http_conf_obj = $self->_get_apache_conf_datastore_obj();

    my ( $iplist_ar, $iplist_ssl_ar );
    if (    ( $OPTS{'iplist_ar'} && ref $OPTS{'iplist_ar'} eq 'ARRAY' )
        and ( $OPTS{'iplist_ssl_ar'} && ref $OPTS{'iplist_ssl_ar'} eq 'ARRAY' ) ) {
        $iplist_ar     = $OPTS{'iplist_ar'};
        $iplist_ssl_ar = $OPTS{'iplist_ssl_ar'};
    }
    else {
        ( $iplist_ar, $iplist_ssl_ar ) = _get_ip_lists_from_apache_ds_obj($http_conf_obj);
    }

    my $proxy_vhosts_info_hr;
    if ( ref $OPTS{'proxy_vhosts_info_hr'} eq 'HASH'
        and defined $OPTS{'proxy_vhosts_info_hr'}->{'non_ssl_vhost_start'} ) {
        $proxy_vhosts_info_hr = $OPTS{'proxy_vhosts_info_hr'};
    }
    else {
        $proxy_vhosts_info_hr = $self->_get_proxy_subdomains_data();
    }

    return
      if !( ref $OPTS{'proxy_vhosts_info_hr'} eq 'HASH' and defined $OPTS{'proxy_vhosts_info_hr'}{'non_ssl_vhost_start'} );

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();
    my $proxy_comment_line;
    if ( $cpconf_ref->{'autodiscover_proxy_subdomains'} ) {
        $proxy_comment_line = '# CPANEL/WHM/WEBMAIL/WEBDISK/AUTOCONFIG PROXY SUBDOMAINS';
    }
    else {
        $proxy_comment_line = '# CPANEL/WHM/WEBMAIL/WEBDISK PROXY SUBDOMAINS';
    }

    # Update non-SSL vhosts
    my $growth = $self->_update_proxy_virtualhosts(
        $iplist_ar,
        {
            proxy_comment_line => $proxy_comment_line,
            sample_vhost       => $proxy_vhosts_info_hr->{sample_vhost},
            start              => $proxy_vhosts_info_hr->{non_ssl_vhost_start},
            end                => $proxy_vhosts_info_hr->{non_ssl_vhost_end},
        }
    );

    # update SSL vhosts
    if ( $proxy_vhosts_info_hr->{ssl_vhost_start} and $proxy_vhosts_info_hr->{ssl_vhost_end} and $proxy_vhosts_info_hr->{sample_vhost_ssl} ) {
        $self->_update_proxy_virtualhosts(
            $iplist_ssl_ar,
            {
                proxy_comment_line => $proxy_comment_line,
                sample_vhost       => $proxy_vhosts_info_hr->{sample_vhost_ssl},
                start              => $proxy_vhosts_info_hr->{ssl_vhost_start} + $growth,
                end                => $proxy_vhosts_info_hr->{ssl_vhost_end} + $growth,
            }
        );
    }

    $self->_get_apache_conf_datastore_obj()->set_proxy_subdomains_start( $proxy_vhosts_info_hr->{non_ssl_vhost_start} );

    return 1;
}

sub _update_proxy_virtualhosts {
    my ( $self, $iplist_ar, $vhost_info_hr ) = @_;
    my @new_proxy_vhosts;

    while ( my @ip_block = splice @$iplist_ar, 0, $IPS_PER_PROXY_SUBDOMAINS_VHOST ) {
        my $new_ips         = join( q{ }, @ip_block );
        my $new_proxy_vhost = $vhost_info_hr->{sample_vhost};

        $new_proxy_vhost =~ s{(<VirtualHost[ \t]+)([^>]+)}{$1$new_ips};
        push @new_proxy_vhosts, ( "\n" . $vhost_info_hr->{proxy_comment_line} . $new_proxy_vhost );
    }

    my $new_vhost = join( q{}, @new_proxy_vhosts );
    my $growth    = length($new_vhost) - ( $vhost_info_hr->{end} - $vhost_info_hr->{start} );

    $self->_httpd_conf_substr(
        $vhost_info_hr->{start},
        $vhost_info_hr->{end} - $vhost_info_hr->{start},
        $new_vhost,
    );

    return $growth;
}

sub _get_ip_lists_from_apache_ds_obj {
    my $http_conf_obj  = shift;
    my $ips_in_ipmap   = $http_conf_obj->fetch_ip_map();
    my $httpd_port     = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    my $httpd_ssl_port = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

    my $ssl_ips_ipmap = {};
    foreach my $ip_port ( keys %{$ips_in_ipmap} ) {
        my ( $ip, $port ) = $ip_port =~ m/^(.*?):(\d+)$/;
        $ssl_ips_ipmap->{"$ip:$httpd_ssl_port"} = 1;
        delete $ips_in_ipmap->{$ip_port} if $port == $httpd_ssl_port;
    }
    delete $ips_in_ipmap->{'*'};
    delete $ips_in_ipmap->{ '*:' . $httpd_port };
    delete $ssl_ips_ipmap->{ '*:' . $httpd_ssl_port };

    require Cpanel::DomainForward;
    if ( my $domainfwdip = Cpanel::DomainForward::get_domain_fwd_ip() ) {
        delete $ips_in_ipmap->{ $domainfwdip . ':' . $httpd_port };
        delete $ssl_ips_ipmap->{ $domainfwdip . ':' . $httpd_ssl_port };
    }
    $ips_in_ipmap->{ '127.0.0.1:' . $httpd_port }      = 1;
    $ssl_ips_ipmap->{ '127.0.0.1:' . $httpd_ssl_port } = 1;

    return ( $ips_in_ipmap, $ssl_ips_ipmap );
}

# This method takes the hashref returned by _get_proxy_subdomains_data(), and
# compares the IPs in the virtualhost against the IPs in apache's datastore. If there are any IPs missing,
# then it'll return a 'reason' to update the service (formerly proxy) subdomain section in httpd.conf
# along with array refs that contain the IPs each virtualhost block should contain.
sub _proxy_subdomain_ip_check {
    my ( $self, $proxy_vhosts_info_hr ) = @_;

    my $ips_in_proxy_vhost     = delete $proxy_vhosts_info_hr->{'ips_in_proxy_vhost'};
    my $ips_in_proxy_vhost_ssl = delete $proxy_vhosts_info_hr->{'ips_in_proxy_vhost_ssl'};

    my $httpdconf_transaction = $self->_get_httpd_conf_transaction_obj();
    my $httpdconf_text_ref    = $httpdconf_transaction->get_data();

    my $httpd_port     = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    my $httpd_ssl_port = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

    my $http_conf_obj = $self->_get_apache_conf_datastore_obj();
    my ( $ips_in_ipmap, $ssl_ips_ipmap ) = _get_ip_lists_from_apache_ds_obj($http_conf_obj);

    #Get this now so we can alter both of the hashes above to determine
    #if any action is necessary.
    my @ipmap_iplist    = sort keys %$ips_in_ipmap;
    my @ipmap_ssliplist = sort keys %$ssl_ips_ipmap;

    my $reason_to_update_vhost;

    delete @{$ips_in_ipmap}{ keys %$ips_in_proxy_vhost };
    delete @{$ssl_ips_ipmap}{ keys %$ips_in_proxy_vhost_ssl };
    if (%$ips_in_ipmap) {
        $reason_to_update_vhost = "Missing IPs to be added to service subdomains vhost: " . join( ',', sort keys %$ips_in_ipmap );
    }
    elsif (%$ssl_ips_ipmap) {
        $reason_to_update_vhost = "Missing IPs to be added to service subdomains SSL vhost: " . join( ',', sort keys %$ssl_ips_ipmap );
    }
    else {
        delete @{$ips_in_proxy_vhost}{@ipmap_iplist};
        delete @{$ips_in_proxy_vhost_ssl}{@ipmap_ssliplist};
        if (%$ips_in_proxy_vhost) {
            $reason_to_update_vhost = "Extra IPs to remove from service subdomains vhost: " . join( ',', sort keys %$ips_in_proxy_vhost );
        }
        elsif (%$ips_in_proxy_vhost_ssl) {
            $reason_to_update_vhost = "Extra IPs to remove from service subdomains SSL vhost: " . join( ',', sort keys %$ips_in_proxy_vhost_ssl );
        }
    }

    return ( $reason_to_update_vhost, \@ipmap_iplist, \@ipmap_ssliplist );
}

######################################################
# private accessor methods

sub _get_primary_vhosts_obj {
    my ($self) = @_;

    return $self->{'_primary_vhosts_obj'};
}

sub _get_apache_conf_datastore_obj {
    my ($self) = @_;

    return $self->{'_apache_conf_obj'};
}

sub _get_httpd_conf_transaction_obj {
    my ($self) = @_;

    return $self->{'_transaction_obj'};
}

# End accessor methods
######################################################

###################################################
# Private static methods

#This die()s, so be sure to check for exceptions.
sub _normalize_is_ssl {
    my ($type) = @_;

    if ( !defined $type ) {
        $type = 'std';
    }

    my $is_ssl;
    if ( $type eq 'ssl' ) {
        $is_ssl = 1;
    }
    else {
        die "Unrecognized type: $type" if $type ne 'std';
        $is_ssl = 0;
    }

    return ( $is_ssl, $type );
}

#Args:
#   httpdconf_text: a scalar ref to the httpd.conf text
#   entries: an array ref of entries to add (cf. addVhost)
#
#Returns a hashref of:
#   has_proxy_subdomains (boolean)
#   added_entries (array ref)
sub _add_vhost_text {
    my ( $self, %opts ) = @_;

    my ( $httpdconf_text_sr, $entry ) = @opts{ 'httpdconf_text', 'entry' };
    die 'Need “entry”!' if !$entry;

    my $added_entry;

    my $locations_cache_ref = {
        'proxy_subdomains_start_pos'         => undef,
        'post_virtualhost_include_start_pos' => undef,
    };

    Cpanel::StringFunc::Trim::ws_trim( \$entry );

    my $length_before_namevirtualhosts = length $entry;

    my $ip_port_strings = _add_namevirtualhosts_to_entry_if_needed(
        'entry'             => \$entry,
        'httpdconf_text_sr' => $httpdconf_text_sr
    );

    Cpanel::StringFunc::Trim::ws_trim( \$entry );
    my $servername = get_vhost_servername($entry);

    my $vhost_location_info = $self->_get_vhost_insert_position_for_vhost_entry(
        'entry'               => $entry,
        'httpdconf_text_sr'   => $httpdconf_text_sr,
        'servername'          => $servername,
        'ip_port_strings'     => $ip_port_strings,
        'locations_cache_ref' => $locations_cache_ref,
    );

    my $insert_at_pos = $vhost_location_info->{'insert_vhost_at_pos'};

    #Insert the vhost.
    $self->_httpd_conf_substr(
        $insert_at_pos,    # The first part of httpd.conf before the vhost
        0,                 # don't remove anything
        "\n$entry",        # we always need a new line since start_pos is always at a newline
    );

    #Since what we're inserting now at 'insert_vhost_at_pos' is actually the
    #NameVirtualHost entry (if added), do this to be sure we have the right spot
    #where the actual vhost starts.
    my $actual_vhost_start_position = $vhost_location_info->{'insert_vhost_at_pos'} + length($entry) - $length_before_namevirtualhosts;

    $added_entry = {
        'servername'           => $servername,
        'method'               => $vhost_location_info->{'method'},
        'vhost_entry'          => $entry,
        'vhost_start_position' => $actual_vhost_start_position,       # This is really the position of the \n before the vhost
    };

    return { added_entry => $added_entry, };
}

sub _add_namevirtualhosts_to_entry_if_needed {
    my (%OPTS) = @_;

    my $entry             = $OPTS{'entry'};
    my $httpdconf_text_sr = $OPTS{'httpdconf_text_sr'};

    my $virtualhost_ip_capture_regex = Cpanel::HttpUtils::Vhosts::Regex::VirtualHost_IP_Capture();
    my $httpd_port                   = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();

    my @ip_port_strings;

    return if $$entry !~ $virtualhost_ip_capture_regex;

    my $virtual_host_ips = $1;
    $virtual_host_ips =~ s/\s+$//;

    my $is_ea4 = Cpanel::Config::Httpd::EA4::is_ea4();
    foreach my $vip ( split m/\s+/, $virtual_host_ips ) {    #from ApacheConf.pm
        my ( $version, $ip, $port ) = Cpanel::IP::Parse::parse( $vip, undef, $Cpanel::IP::Parse::BRACKET_IPV6 );
        $port ||= $httpd_port;
        my $ip_port = "$ip:$port";
        if (   !$is_ea4
            && index( ${$httpdconf_text_sr}, "$NAME_VIRTUAL_HOST_DIRECTIVE $ip_port" ) == -1
            && ${$httpdconf_text_sr} !~ m/\n[ \t]*namevirtualhost[ \t]+\Q$ip_port\E\b/si ) {
            $$entry = "$NAME_VIRTUAL_HOST_DIRECTIVE $ip_port\n$$entry";
        }
        push @ip_port_strings, $ip_port;
    }

    return \@ip_port_strings;
}

# _find_wildcard_vhost_insert_position returns the best position to insert a
# wildcard vhost if there are other wildcard vhosts on the ip:port combination.
# This may return undef, in which case there are no wildcard vhosts on the ip:port combination.
sub _find_wildcard_vhost_insert_position {
    my ( $self, $httpdconf_text_sr, $servername, $ip_port_strings ) = @_;

    my $http_conf_obj = $self->_get_apache_conf_datastore_obj();
    my @ips_and_ports = map { [ split( m{:}, $_ ) ] } @$ip_port_strings;

    #This is an array of [ $servername, $port ] elements.
    my @wildcard_servername_port;
    for my $ipport (@ips_and_ports) {
        my $domains_ar = $http_conf_obj->fetch_domains_on_ip_port(@$ipport);
        push @wildcard_servername_port, map { tr{*}{} ? [ $_, $ipport->[1] ] : () } @$domains_ar;
    }

    my $servername_length = length $servername;

    #Find the longest existing wildcard servername that's still shorter than the new one.
    my $insert_before_sn_port;
    for my $sn_port (@wildcard_servername_port) {
        next if length( $sn_port->[0] ) >= $servername_length;

        if ( !$insert_before_sn_port || ( length( $sn_port->[0] ) > length( $insert_before_sn_port->[0] ) ) ) {
            $insert_before_sn_port = $sn_port;
        }
    }

    return if !$insert_before_sn_port;

    return $http_conf_obj->find_vhost_offset_by_servername_port(@$insert_before_sn_port);
}

sub _get_vhost_insert_position_for_vhost_entry {
    my ( $self, %OPTS ) = @_;

    my $entry               = $OPTS{'entry'};
    my $httpdconf_text_sr   = $OPTS{'httpdconf_text_sr'};
    my $locations_cache_ref = $OPTS{'location_cache_ref'};
    my $servername          = $OPTS{'servername'};
    my $ip_port_strings     = $OPTS{'ip_port_strings'};

    my $location_start_pos;
    my $method;

    my $http_conf_obj = $self->_get_apache_conf_datastore_obj();

    # passed in servername is already decoded
    if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($servername) ) {
        $location_start_pos = $self->_find_wildcard_vhost_insert_position( $httpdconf_text_sr, $servername, $ip_port_strings );
        $method             = 'wildcard_match';
    }
    else {
        # This will return the location if there are any non-primary wildcards, if there aren't it'll get undef
        my @offsets = map { $http_conf_obj->find_first_wildcard_offset( split( m{:}, $_ ) ) } @$ip_port_strings;
        $location_start_pos = $offsets[0];               # offsets are always sorted
        $method             = 'before_first_wildcard';
    }

    #"insert_vhost_at_pos" is the position in httpd.conf where the new vhost will go.
    my $insert_vhost_at_pos;

    if ( defined $location_start_pos ) {    #wildcard domain or wildcard primary domain
        $insert_vhost_at_pos = $location_start_pos;
        $locations_cache_ref->{'proxy_subdomains_start_pos'} = $locations_cache_ref->{'post_virtualhost_include_start_pos'} = undef;
    }

    # This is safe because if we match this once, we will not match Include .. post_virtualhost below
    elsif ( $http_conf_obj->get_proxy_subdomains_start() ) {
        $method = 'before_proxy_subdomains';
        $locations_cache_ref->{'proxy_subdomains_start_pos'} ||= $http_conf_obj->get_proxy_subdomains_start();    #This is really the position of \n

        # We don't have to adjust the $post_virtualhost_include_start_pos
        # we will never match it since we got here
        $insert_vhost_at_pos = $locations_cache_ref->{'proxy_subdomains_start_pos'};
    }

    # This is safe because if we match this once, we did not match #... PROXY SUBDOMAINS above
    elsif ( $http_conf_obj->get_post_virtualhost_include_offset() ) {
        $method = 'before_post_virtualhost';
        $locations_cache_ref->{'post_virtualhost_include_start_pos'} ||= $http_conf_obj->get_post_virtualhost_include_offset();    #This is really the position of \n

        # We don't have to adjust the $proxy_subdomains_start_pos since
        # we will never have matched it since we got here
        $insert_vhost_at_pos = $locations_cache_ref->{'post_virtualhost_include_start_pos'};
    }

    #We get here when all of these are true:
    #1) The new vhost's servername is not a wildcard.
    #2) There is no wildcard already on the ip(s)/port(s).
    #3) There is no PROXY SUBDOMAINS block.
    #4) There is no "Include..post_virtualhost" line.
    else {
        $method              = 'end';
        $insert_vhost_at_pos = length ${$httpdconf_text_sr};
    }

    return {
        'method'              => $method,
        'insert_vhost_at_pos' => $insert_vhost_at_pos
    };
}

sub _get_ip_match_regex_string {
    my (@ips_and_ports) = @_;

    my $httpd_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();

    my @ip_port_regex = ();
    for my $ip_port (@ips_and_ports) {
        next if !ref $ip_port;

        if ( !$ip_port->[1] || $ip_port->[1] eq $httpd_port ) {
            push @ip_port_regex, "\Q$ip_port->[0]\E(?::\Q$httpd_port\E)?[^0-9]";
        }
        else {
            push @ip_port_regex, "\Q$ip_port->[0]:$ip_port->[1]\E[^0-9]";
        }
    }

    # Not all vhosts need to have a port alongside an ip address. To accomodate that, we need to optionally look for the default httpd port
    return join( '|', @ip_port_regex );
}

sub _load_locale {

    # Cpanel::LoadModule::loadmodule already logs if it can't load the module
    if ( $locale || Cpanel::LoadModule::loadmodule('Locale') ) {
        return $locale ||= Cpanel::Locale->get_handle();
    }
    return;
}

sub get_vhost_servername {
    my ($vhost_entry) = @_;

    return unless defined $vhost_entry;

    $vhost_servername_capture_regex ||= Cpanel::ApacheConf::Parser::Regex::VirtualHost_ServerName_Capture();
    if ( $vhost_entry =~ m{$vhost_servername_capture_regex}o ) {
        my $servername = $1;
        $servername = lc $servername;
        return Cpanel::WildcardDomain::decode_wildcard_domain($servername);
    }

    return;
}

#Returns an array ref of 2-member array refs,
#or undef if the vhost entry can't be parsed for IP/port data.
sub get_vhost_ips_ports {
    my ($vhost_entry) = @_;

    return unless defined $vhost_entry;

    $vhost_ip_capture_regex ||= Cpanel::HttpUtils::Vhosts::Regex::VirtualHost_IP_Capture();
    return if $vhost_entry !~ m{$vhost_ip_capture_regex}o;
    my $ips = $1;
    $ips =~ s{\s+\z}{};

    #For wildcard IPs, the entry will be [ '*', '*' ].
    #For normal IPs, the entry is [ $ip, $port ].

    my @ip_map;
    foreach my $ip ( split( /\s+/, $ips ) ) {
        if ( $ip eq '*' ) {
            push( @ip_map, [ '*', '*' ] );
        }
        ## e.g. [2001:db8::dead:beef]:80
        elsif ( $ip =~ m/^\[(.*?)\]\:(\d+)$/ ) {
            push( @ip_map, [ $1, $2 ] );
        }
        ## e.g. [2001:db8::dead:beef]
        elsif ( $ip =~ m/^\[(.*?)\]$/ ) {
            push( @ip_map, [$1] );
        }
        ## e.g. 192.0.2.120:80
        elsif ( $ip =~ m/^(\d+\.\d+\.\d+\.\d+)\:(\d+)$/ ) {
            push( @ip_map, [ $1, $2 ] );
        }
        ## e.g. 192.0.2.120
        elsif ( $ip =~ m/^(\d+\.\d+\.\d+\.\d+)$/ ) {
            push( @ip_map, [$1] );
        }
        ## ipv6 addy:port $1 : $2 w/o brackets (shouldn't exist in the wild)\n";
        elsif ( $ip =~ m/^(.+\:.+\:.+)\:(\d+)$/ ) {
            push( @ip_map, [ $1, $2 ] );
        }
        else {
            # Unknown IP:Port type/combination
        }
    }
    return \@ip_map;
}

1;

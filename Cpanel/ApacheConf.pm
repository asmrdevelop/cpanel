package Cpanel::ApacheConf;

# cpanel - Cpanel/ApacheConf.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ApacheConf::Parser ();
use Cpanel::XSLib              ();
use Cpanel::JSON               ();
use Cpanel::Debug              ();
use Cpanel::ConfigFiles::Httpd ();
use Cpanel::Fcntl              ();
use Cpanel::Transaction        ();

*VERSION = \$Cpanel::ApacheConf::Parser::VERSION;

#CONSTANT
our $SKIP_CACHE_REBUILD  = 1;
our $FORCE_REBUILD_CACHE = 2;

our $MEMORY_CACHE_IS_IN_SYNC = 1;
our $FORCE_WRITE_DATASTORE   = 1;

my $apacheconf_data_mtime = 0;
my $apacheconf_data;

# Shortcut for speed since this is called in tight loops
*get_vhost_offset_key = *Cpanel::ApacheConf::Parser::get_vhost_offset_key;

sub new {
    my ( $class, %opts ) = @_;

    if ($Cpanel::HttpUtils::Config::Apache::ACTIVE_OBJECT) {
        return $Cpanel::HttpUtils::Config::Apache::ACTIVE_OBJECT->_get_apache_conf_datastore_obj();
    }

    #This might be undef.
    my $httpd_conf_transaction = $opts{'httpd_conf_transaction'};

    my $self = bless {
        _instantiator_gave_transaction => $opts{'httpd_conf_transaction'} ? 1 : 0,
    }, $class;

    #maybe_httpdconf_trans is only defined if we had to rebuild the cache file.
    my ( $data, $maybe_httpdconf_trans, $conf_path, $cache_needs_to_be_updated ) = _loadhttpdconf_and_transaction(
        0,
        httpd_conf_transaction => $httpd_conf_transaction,    #Could be undef
        cache_rebuild          => $SKIP_CACHE_REBUILD
    );

    if ( !$data ) {
        Cpanel::Debug::log_panic("Failed to read the Apache configuration file or its datastore cache!");
    }

    $self->{'data'}                    = $data;
    $self->{'data_modified'}           = $cache_needs_to_be_updated;
    $self->{'_httpd_conf_transaction'} = $httpd_conf_transaction || $maybe_httpdconf_trans;

    return $self;
}

sub rebuild {
    my $self = shift;

    # Since we're passing 0 for 'not_fatal' this should die if it fails
    my ($data) = _loadhttpdconf_and_transaction(
        0,
        httpd_conf_transaction => $self->{'_httpd_conf_transaction'},
        cache_rebuild          => $FORCE_REBUILD_CACHE,
    );

    # just in case the above notion isn't correct
    if ( !$data ) {
        Cpanel::Debug::log_panic("Failed to read the Apache configuration file or its datastore cache!");
    }

    $self->{'data'} = $data;

    return $self;
}

sub destroy {
    my ( $self, $memory_cache_is_synced, $force_write_datastore ) = @_;

    my ( $ok, $msg );
    if ( $force_write_datastore || $self->{'data_modified'} ) {
        if ( !$self->{'_instantiator_gave_transaction'} ) {
            Cpanel::Debug::log_invalid("destory called with modified data when instantiator did not give transaction. Cpanel::HttpUtils::Config::Apache must be used for edits to ensure consistency.");
        }

        my ( $ds_ok, $ds_trans ) = Cpanel::Transaction::get_httpd_conf_datastore();    #  Transactions are now smart enough to only read on demand which makes skip_init_data obsolete
        if ( !$ds_ok ) {
            Cpanel::Debug::log_warn("Could not lock Apache configuration datastore: $ds_trans");
            return;
        }

        my $time_before_write = time();

        $ds_trans->set_data($apacheconf_data);
        ( $ok, $msg ) = $ds_trans->save_and_close();

        #NB: An instance of this package does NOT keep a lock on the datastore file. Only the httpd.conf if needed to rebuild or passed in.
        if ( !$ok ) {
            Cpanel::Debug::log_warn("Could not unlock the Apache configuration datastore: $msg");
        }

        if ( $ok && $memory_cache_is_synced ) {
            $self->{'data_modified'} = 0;                    #We saved successfully, yay!
            $apacheconf_data_mtime = $time_before_write;
        }

        if ( !$ok ) {
            Cpanel::Debug::log_warn("Could not save Apache configuration datastore: $msg");
        }

        # case 145741: previously we returned here before we could
        # destory the transaction object.  This would cause the system
        # to have a unknown failure because the lock would be left open.
    }

    #Since we created the httpd.conf lock/transaction, we should end it.
    if ( !$self->{'_instantiator_gave_transaction'} && $self->{'_httpd_conf_transaction'} ) {
        my ( $ok, $msg ) = $self->{'_httpd_conf_transaction'}->close();
        if ( !$ok ) {
            Cpanel::Debug::log_warn("Could not unlock the Apache configuration: $msg");
        }
    }

    return ( $ok, $msg );
}

sub clear_memory_cache {
    $apacheconf_data_mtime = 0;
    %$apacheconf_data      = ();

    return;
}

sub clearcache {
    clear_memory_cache();
    my $httpdconf = Cpanel::ConfigFiles::Httpd::find_httpconf(1);
    if ($httpdconf) {
        unlink( $httpdconf . '.datastore' );
    }

    return;
}

sub find_first_servername_on_ip_port {
    my ( $self, $ip, $port ) = @_;

    my $offset_servername_hr = $self->_find_offset_servernames_on_ip_port( $ip, $port );

    return undef if !$offset_servername_hr || !%$offset_servername_hr;

    return $offset_servername_hr->{ ( sort { $a <=> $b } keys %$offset_servername_hr )[0] };
}

sub _find_offset_servernames_on_ip_port {
    my ( $self, $ip, $port ) = @_;

    my $ip_port_servernames_ar = $self->_get_ip_port_servernames_ar( $ip, $port ) or return;

    return $self->_find_offset_from_port_servernames( $port, $ip_port_servernames_ar );
}

sub _find_offset_from_port_servernames {
    my ( $self, $port, $server_names_ar ) = @_;
    my $vhosts_offsets    = $self->{'data'}{'__vhosts_offsets__'};
    my %offset_servername = map {
        (
            $vhosts_offsets->{
                "$_ $port"    # get_vhost_offset_key($_,$port)
            } // '__MISSING__'
        ) => $_
    } @$server_names_ar;

    delete $offset_servername{'__MISSING__'};

    return \%offset_servername;

}

sub find_first_wildcard_offset {
    my ( $self, $ip, $port ) = @_;

    my $wildcard_offset_servername_hr = $self->_find_wildcard_offset_servernames_on_ip_port( $ip, $port );

    return ( sort { $a <=> $b } keys %$wildcard_offset_servername_hr )[0];
}

sub _find_wildcard_offset_servernames_on_ip_port {
    my ( $self, $ip, $port ) = @_;
    my $ip_port_servernames_ar = $self->_get_ip_port_servernames_ar( $ip, $port ) or return;

    return if Cpanel::XSLib::get_array_index_start_chr( $ip_port_servernames_ar, ord '*' ) == -1;

    return $self->_find_offset_from_port_servernames( $port, [ grep { index( $_, '*' ) == 0 } @$ip_port_servernames_ar ] );
}

sub _get_ip_port_servernames_ar {
    my ( $self, $ip, $port ) = @_;
    my $ipmap = $self->{'data'}{'__ipmap__'};
    return if !$ipmap->{$ip};

    my $ip_port_servernames_ar = $ipmap->{$ip}{$port};
    return if !$ip_port_servernames_ar || !@$ip_port_servernames_ar;

    return $ip_port_servernames_ar;
}

# Called in tight loops
sub find_vhost_offset_by_servername_port {    ##no critic qw(RequireArgUnpacking)
                                              #my ( $self, $servername, $port ) = @_;
    return $_[0]->{'data'}{'__vhosts_offsets__'}{ get_vhost_offset_key( $_[1], $_[2] ) };
}

sub find_homedir_servername_ports {
    my ( $self, $homedir ) = @_;

    my @servernames;
    my $homedir_length = length $homedir;

    while ( my ( $servername, $attrs_hr ) = each %{ $self->{'data'} } ) {
        next if !ref $attrs_hr;
        next if substr( $servername, 0, 1 ) eq '_' || !$attrs_hr->{'docroot'} || substr( $attrs_hr->{'docroot'}, 0, $homedir_length ) ne $homedir;
        if ( $attrs_hr->{'docroot'} =~ m{\A\Q$homedir\E(?:/|\z)} ) {
            for my $address_hr ( @{ $attrs_hr->{'address'} } ) {
                push @servernames, [ $servername, $address_hr->{'port'} ];
            }
        }
    }

    return \@servernames;
}

sub get_proxy_subdomains_start {
    my ($self) = @_;

    return $self->{'data'}{'__proxy_start__'};
}

sub set_proxy_subdomains_start {
    my ( $self, $new_value ) = @_;

    return $self->{'data'}{'__proxy_start__'} = $new_value;
}

sub get_post_virtualhost_include_offset {
    my ($self) = @_;

    return $self->{'data'}{'__post_virtualhost_include_offset__'};
}

#Returns an address entry.
#NOTE: Whatever calls this probably also needs to call update_vhost_offsets!!
sub remove_record {
    my ( $self, $servername, $port ) = @_;

    $self->{'data_modified'} = 1;

    my $data = $self->{'data'};

    my %removed_from_ips;

    my $removed;

    delete $data->{'__vhosts_offsets__'}{ get_vhost_offset_key( $servername, $port ) };

    my $addresses_ar = $data->{$servername}{'address'};
    for my $i ( reverse( 0 .. $#$addresses_ar ) ) {
        if ( $addresses_ar->[$i]{'port'} == $port ) {
            $removed_from_ips{ $addresses_ar->[$i]{'ip'} } = undef;
            $removed = splice( @$addresses_ar, $i, 1 );
        }
    }

    for my $ip ( keys %removed_from_ips ) {
        my $port_domains_hr = $data->{'__ipmap__'}{$ip};

        Cpanel::XSLib::filter_one( $port_domains_hr->{$port}, $servername );

        if ( !@{ $port_domains_hr->{$port} } ) {
            delete $port_domains_hr->{$port};
        }
        if ( !%$port_domains_hr ) {
            delete $data->{'__ipmap__'}{$ip};
        }
    }

    if ( !@$addresses_ar ) {
        my $deleted = delete $data->{$servername};
        if ( $deleted && $deleted->{'aliases'} ) {
            delete @{ $data->{'__aliasmap__'} }{ @{ $deleted->{'aliases'} } };
        }
    }

    return $removed;
}

sub fetch_ip_map {
    my $self = shift;

    $self = { 'data' => scalar loadhttpdconf() } if ref $self ne __PACKAGE__;

    my %MAP;

    my $ipmap = $self->{'data'}{'__ipmap__'};

    foreach my $ip ( keys %$ipmap ) {
        foreach my $port ( keys %{ $ipmap->{$ip} } ) {
            $MAP{"$ip:$port"} = 1;
        }
    }

    return \%MAP;
}

#Can be called statically (i.e., as a class method) or dynamically (as an instance method).
#
#e.g.: $apacheconf->fetch_domains_on_ip_port( $ip, $port );
#      fetch_domains_on_ip_port( $ip, $port )
sub fetch_domains_on_ip_port {
    my ( $self_or_ip, $ip_or_port, $port ) = @_;

    my ( $data, $ip );
    if ( ref $self_or_ip eq __PACKAGE__ ) {
        $data = $self_or_ip->{'data'};
        $ip   = $ip_or_port;
    }
    else {
        $ip   = $self_or_ip;
        $port = $ip_or_port;
        $data = loadhttpdconf();
    }

    return [] if !$data->{'__ipmap__'} || !$data->{'__ipmap__'}{$ip} || !$data->{'__ipmap__'}{$ip}{$port};

    # This could be a very large array. Because of that we
    # return the internal reference rather than a copy.
    return $data->{'__ipmap__'}{$ip}{$port};
}

sub set_vhost_offset {
    my ( $self, $servername, $port, $new_offset ) = @_;

    $self->{'data'}{'__vhosts_offsets__'}{ get_vhost_offset_key( $servername, $port ) } = $new_offset;

    return;
}

sub update_vhost_offsets {
    my ( $self, $start, $net_growth ) = @_;

    return if !$net_growth;

    my $dataref = $self->{'data'};

    #NOTE: This is often a tight loop, so even small optimizations can be valuable here.
    Cpanel::XSLib::increase_hash_values_past_threshold(
        $dataref->{'__vhosts_offsets__'},
        $start,
        $net_growth,
    );

    for my $index (qw( __proxy_start__  __post_virtualhost_include_offset__ )) {
        if ( $dataref->{$index} && $dataref->{$index} >= $start ) {    # must be >= in case we
                                                                       # we are updating ourselves
            $dataref->{$index} += $net_growth;
        }
    }

    return;
}

sub add_record {
    my ( $self, $vhost_entry, $opts ) = @_;

    die 'Need vhost entry!' if !length $vhost_entry;

    $opts ||= {};
    $opts->{'position'} ||= 'end';

    # only vhost_entry is required

    $self->{'data_modified'} = 1;

    # We parse the vhost instead of getting it as a data structure because we need to support templates
    my $parsed_record = Cpanel::ApacheConf::Parser::vhost_record_parser( \$vhost_entry );
    my $record;

    my $servername = ( grep { index( $_, '__' ) != 0 } keys %{$parsed_record} )[0];    # The server name is obtained from the parser

    if ( !$servername ) {
        require Carp;
        die Carp::longmess("No ServerName directive in vhost: $vhost_entry");
    }

    $record = $parsed_record->{$servername};

    my $aliasmap                            = $self->{'data'}{'__aliasmap__'};
    my $check_for_servername_in_address_map = 0;

    # We are replacing the record
    if ( exists $self->{'data'}->{$servername} ) {
        $check_for_servername_in_address_map = _vhosts_on_port_have_been_replaced( $record, $self->{'data'}{$servername} );

        # Clear all the existing aliases for this host
        if ( defined $aliasmap && $self->{'data'}->{$servername}{'aliases'} ) {
            my @old_aliases = @{ $self->{'data'}->{$servername}{'aliases'} };
            delete @{$aliasmap}{@old_aliases};
        }

        if ( $record->{'aliases'} ) {
            $self->{'data'}->{$servername}{'aliases'} = $record->{'aliases'};
        }
        else {
            delete $self->{'data'}->{$servername}{'aliases'};
        }

        # case 84781: We do not need to merge aliases because aliases are always the same for SSL and
        # non-SSL vhosts.  Its only the addresses that need to be merged.
        foreach my $merge_element ('address') {

            #
            #  $current_items_ar will be all the current aliases or addresses
            #  for the vhost
            #
            my $current_items_ar = $self->{'data'}->{$servername}->{$merge_element};

            #
            #  $new_items_to_add_ar will be all the new addresses or aliases
            #  we need to merge into the existing vhost
            #
            my $new_items_to_add_ar = $record->{$merge_element};
            my $create_index_cr;
            #
            #  aliases and address should both be array refs
            #
            if ( ref $current_items_ar && ref $new_items_to_add_ar ) {

                #Addresses are stored as { ip => "..", port => ".." },
                #so in order to check for duplicate addresses we have to
                #create an "indexing" function that creates a string
                #from the address hash contents.
                if ( !ref $new_items_to_add_ar->[0] ) {
                    $create_index_cr = sub { return shift };
                }
                elsif ( 'HASH' eq ref $current_items_ar->[0] ) {
                    $create_index_cr = sub {
                        my $hashref = shift;
                        return join( "\n", map { $_, $hashref->{$_} } sort keys %$hashref );
                    };
                }
                elsif ( 'ARRAY' eq ref $current_items_ar && !@{$current_items_ar} ) {

                    # If the current list is empty, we can just fill it ith the new items
                    @{$current_items_ar} = @{$new_items_to_add_ar};
                    next;
                }
                else {
                    Cpanel::Debug::log_warn( "add_record does not know how to index $merge_element with type:" . ( scalar ref $current_items_ar ) );
                    next;
                }
                #
                #  This create_index_cr will make the data
                #  into a string that can be used as in index
                #  example { 'ip' => '1.2.3.4', port => 80 } will become "ip\n1.2.3.4\nport\n80"
                #  example "bob.org" will become "bob.org"
                #
                my %current_keys = map { $create_index_cr->($_) => 1 } @$current_items_ar;

                foreach my $new_item (@$new_items_to_add_ar) {

                    #
                    #  Next we make the new data to add into
                    #  a string that can be used as in index
                    #  in the same format as the current_keys
                    #  that we did above.
                    #
                    my $index = $create_index_cr->($new_item);

                    #
                    #  Since we have a string that represents
                    #  the new key to add we can compare it
                    #  against the strings we have for all the current
                    #  keys and know if we have a duplicate
                    #
                    if ( !$current_keys{$index} ) {
                        push @$current_items_ar, $new_item;
                    }
                }
            }
        }
    }
    else {
        $self->{'data'}->{$servername} = $record;
    }
    if ( exists $record->{'aliases'} ) {
        foreach my $alias ( @{ $record->{'aliases'} } ) {
            $aliasmap->{$alias} = $servername;
        }
    }

    #Update the ipmap.
    if ( exists $record->{'address'} ) {
        $self->{'data'}{'__ipmap__'} ||= {};
        my $ipmap = $self->{'data'}{'__ipmap__'};
        my ( $ip, $port );
        foreach my $address ( @{ $record->{'address'} } ) {
            ( $ip, $port ) = @{$address}{qw(ip port)};
            if ($check_for_servername_in_address_map) {
                @{ $ipmap->{$ip}{$port} } = grep { $_ ne $servername } @{ $ipmap->{$ip}{$port} };
            }
            if ( $opts->{'position'} eq 'end' ) {
                push @{ $ipmap->{$ip}{$port} }, $servername;
            }
            else {
                unshift @{ $ipmap->{$ip}{$port} }, $servername;
            }
        }
    }

    return 1;
}

#This code, for legacy reasons, can both die() and return undef.
#Account for both, O ye caller.
sub loadhttpdconf {
    my ($not_fatal) = @_;

    if ($Cpanel::HttpUtils::Config::Apache::ACTIVE_OBJECT) {
        my $ds_object = $Cpanel::HttpUtils::Config::Apache::ACTIVE_OBJECT->_get_apache_conf_datastore_obj();
        return wantarray ? %{ $ds_object->{'data'} } : $ds_object->{'data'};

    }

    my ( $apache_conf_hr, $ds_transaction ) = _loadhttpdconf_and_transaction($not_fatal);

    return if !$apache_conf_hr;

    #_loadhttpdconf_and_transaction(), if it had to read httpd.conf itself,
    #passes the lock on that file back in case a caller needs it.
    #loadhttpdconf(), however, is read-only, so we always close the lock here.
    #TODO: Avoid locking httpd.conf if we don't need to.
    if ($ds_transaction) {
        my ( $ok, $msg ) = $ds_transaction->close();
        if ( !$ok ) {
            Cpanel::Debug::log_warn("Could not unlock the Apache configuration: $msg");
        }
    }

    return wantarray ? %$apache_conf_hr : $apache_conf_hr;
}

#This code, for legacy reasons, can both die() and return undef.
#Account for both, O ye caller.
sub _loadhttpdconf_and_transaction {
    my ( $not_fatal, %opts ) = @_;

    my $httpdconf = Cpanel::ConfigFiles::Httpd::find_httpconf($not_fatal);

    return if !$httpdconf;

    my $httpd_conf_transaction = $opts{'httpd_conf_transaction'};
    my $passed_in_transaction  = $httpd_conf_transaction ? 1 : 0;
    my $cache_rebuild          = $opts{'cache_rebuild'} || 0;

    my $httpd_conf_mtime = ( stat($httpdconf) )[9];

    my $datastore_file = "$httpdconf.datastore";

    if ( !$passed_in_transaction ) {

        # We cannot use the memory cache if we passed in the transaction because
        # it could have been modified before we recieved the httpd_conf_transaction
        # lock
        if (   $cache_rebuild != $FORCE_REBUILD_CACHE
            && $apacheconf_data_mtime >= $httpd_conf_mtime
            && -e "$httpdconf.datastore"
            && scalar keys %$apacheconf_data ) {
            return $apacheconf_data;
        }
    }

    #Can't use the memory cache, so we go to the disk.
    $apacheconf_data_mtime = 0;
    if ( tied %$apacheconf_data ) {
        untie %$apacheconf_data;
    }
    $apacheconf_data = undef;

    my $datastore_file_size = -s $datastore_file;

    if ( $datastore_file_size && ( $cache_rebuild != $FORCE_REBUILD_CACHE ) ) {
        my $datastore_mtime = ( stat(_) )[9];
        my $now             = _time();
        if ( $httpd_conf_mtime <= $datastore_mtime && $datastore_mtime <= $now ) {    #timewarp safe
            local $@;

            #We don't care if this fails because we'll just rebuild below.
            my $res = eval { Cpanel::JSON::LoadFile($datastore_file) };

            if ( $res && $res->{'__version__'} && $res->{'__ipmap__'} && $res->{'__aliasmap__'} && ( $res->{'__version__'} eq $Cpanel::ApacheConf::Parser::VERSION ) ) {
                $apacheconf_data       = $res;
                $apacheconf_data_mtime = $datastore_mtime;

                return $res;
            }
        }
    }

    #No datastore file, so we have to rebuild.
    if ( !$httpd_conf_transaction ) {
        my $lock_ok;
        ( $lock_ok, $httpd_conf_transaction ) = Cpanel::Transaction::get_httpd_conf();
        Cpanel::Debug::log_die("Could not lock Apache configuration: $httpd_conf_transaction") if !$lock_ok;
    }

    # vhost_record_parser now supports an indefinite number of records
    # It also now handles the case were there are multiple proxy
    # subdomains vhosts correctly
    my $records_ref = Cpanel::ApacheConf::Parser::vhost_record_parser( $httpd_conf_transaction->get_data() );
    $apacheconf_data                  = $records_ref;
    $apacheconf_data->{'__version__'} = $Cpanel::ApacheConf::Parser::VERSION;
    $apacheconf_data_mtime            = $httpd_conf_mtime;

    my $data_modified = 1;

    if ( $cache_rebuild != $SKIP_CACHE_REBUILD ) {

        #Don't try to read in the file contents; instead, zero it out right away.
        my ( $ok, $trans_obj ) = Cpanel::Transaction::get_httpd_conf_datastore( sysopen_flags => Cpanel::Fcntl::or_flags(qw( O_TRUNC O_CREAT )) );
        if ( !$ok ) {
            Cpanel::Debug::log_warn("Could not rewrite Apache configuration datastore file: $trans_obj");
        }
        else {
            $trans_obj->set_data($apacheconf_data);

            my ( $ok, $err ) = $trans_obj->save();
            if ($ok) {
                $data_modified = 0;    #We saved successfully, yay!
            }
            else {
                Cpanel::Debug::log_warn("Could not write to Apache configuration datastore file: $err");
            }
            ( $ok, $err ) = $trans_obj->close();
            if ( !$ok ) {
                Cpanel::Debug::log_warn("Could not unlock the Apache configuration datastore file: $err");
            }
        }
    }

    return ( $apacheconf_data, $httpd_conf_transaction, $httpdconf, $data_modified );
}

#for testing only
sub _set_apacheconf_data {
    my $data = shift;

    $apacheconf_data = $data;
    return 1;
}

sub _vhosts_on_port_have_been_replaced {
    my ( $new_record, $old_record ) = @_;

    return 1 if !$new_record->{'address'} || !$old_record->{'address'};

    my %new_ports = map { $_->{'port'} => 1 } @{ $new_record->{'address'} };
    my %old_ports = map { $_->{'port'} => 1 } @{ $old_record->{'address'} };
    if ( scalar keys %new_ports == 1 && scalar keys %old_ports == 1 ) {
        if ( ( keys %new_ports )[0] == ( keys %old_ports )[0] ) {

            # same port, definately check_for_servername_in_address_map
            return 1;
        }
        else {
            return 0;
        }
    }

    # multiple ports, assume check_for_servername_in_address_map
    return 1;
}

*_time = \&CORE::time;

1;

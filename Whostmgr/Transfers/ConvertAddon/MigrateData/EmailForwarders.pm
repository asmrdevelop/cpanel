package Whostmgr::Transfers::ConvertAddon::MigrateData::EmailForwarders;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/EmailForwarders.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData);

use File::Spec                      ();
use Cpanel::LoadFile                ();
use Cpanel::TempFile                ();
use Cpanel::Exception               ();
use Cpanel::FileUtils::Copy         ();
use Cpanel::FileUtils::Write        ();
use Whostmgr::Email::Autoresponders ();

sub new {
    my ( $class, $opts ) = @_;

    my $self = $class->SUPER::new($opts);
    $self->{'tmpfile_obj'} = Cpanel::TempFile->new();
    $self->{'tmpdir'}      = $self->{'tmpfile_obj'}->dir();
    return $self;
}

sub save_forwarders_for_domain {
    my ( $self, $domain ) = @_;
    return if !$domain;

    my $valiases = File::Spec->catfile( '/etc', 'valiases', $domain );
    if ( -e $valiases ) {
        my $tmpfile = File::Spec->catfile( $self->{'tmpdir'}, 'valiases_' . $domain );
        my ( $ok, $err ) = Cpanel::FileUtils::Copy::safecopy( $valiases, $tmpfile );
        $self->add_warning($err) if !$ok;
        $self->{$domain}->{'valiases'} = $tmpfile;
    }

    my $vdomainaliases = File::Spec->catfile( '/etc', 'vdomainaliases', $domain );
    if ( -e $vdomainaliases ) {
        my $tmpfile = File::Spec->catfile( $self->{'tmpdir'}, 'vdomainaliases_' . $domain );
        my ( $ok, $err ) = Cpanel::FileUtils::Copy::safecopy( $vdomainaliases, $tmpfile );
        $self->add_warning($err) if !$ok;
        $self->{$domain}->{'vdomainaliases'} = $tmpfile;
    }

    return 1;
}

sub restore_forwarders_for_domain {
    my ( $self, $domain ) = @_;
    if ( !$domain ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a domain name' );    ## no extract maketext (developer error message. no need to translate)
    }

    $self->ensure_users_exist();

    foreach my $file ( keys %{ $self->{$domain} } ) {
        my $dest = File::Spec->catfile( '/etc', $file, $domain );

        if ( $file eq 'valiases' ) {
            my $processed_data = $self->_process_valiases_file( $self->{$domain}->{$file} );
            Cpanel::FileUtils::Write::overwrite_no_exceptions( $dest, join( "\n", @{$processed_data} ) . "\n", 0640 )
              or $self->add_warning("Failed to write “$dest”: $!");
        }
        else {
            my ( $ok, $err ) = Cpanel::FileUtils::Copy::safecopy( $self->{$domain}->{$file}, $dest );
            $self->add_warning($err) if !$ok;
        }

        chown scalar getpwnam( $self->{'to_username'} ), scalar getgrnam('mail'), $dest
          or $self->add_warning("Failed to chown “$dest”: $!");
    }

    return 1;
}

sub restore_forwarders_for_domain_autoresponder_only {
    my ( $self, $domain ) = @_;
    if ( !$domain ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a domain name' );    ## no extract maketext (developer error message. no need to translate)
    }

    $self->ensure_users_exist();

    if ( -e $self->{$domain}->{'valiases'} ) {
        my $dest           = File::Spec->catfile( '/etc', 'valiases', $domain );
        my $processed_data = $self->_process_valiases_file( $self->{$domain}->{'valiases'}, 'autoresponders only' );

        Cpanel::FileUtils::Write::overwrite_no_exceptions( $dest, join( "\n", @{$processed_data} ) . "\n", 0640 )
          or $self->add_warning("Failed to write “$dest”: $!");

        chown scalar getpwnam( $self->{'to_username'} ), scalar getgrnam('mail'), $dest
          or $self->add_warning("Failed to chown “$dest”: $!");
    }

    return 1;
}

sub _process_valiases_file {
    my ( $self, $file, $autoresponder_only ) = @_;
    my $old_auto_respond_dir = Whostmgr::Email::Autoresponders::get_auto_responder_dir( $self->{'from_username'} );
    my $new_auto_respond_dir = Whostmgr::Email::Autoresponders::get_auto_responder_dir( $self->{'to_username'} );

    my $unescaped_comma = qr/(?<!\\)(?:\\\\)*,/;

    my @processed_data;
    my @valiases_data = split /\n/, Cpanel::LoadFile::load($file);
    foreach my $line (@valiases_data) {
        if ( $line =~ m{bin/autorespond} ) {
            $line =~ s/\Q$old_auto_respond_dir\E/$new_auto_respond_dir/g;
            push @processed_data, $line;
        }
        elsif ( $line =~ m{^\*:} ) {
            $line =~ s/(?:$unescaped_comma|[\s:])\K\Q$self->{'from_username'}\E(?=[\s,]|$)/$self->{'to_username'}/g;
            push @processed_data, $line;
        }
        else {
            push @processed_data, $line if !$autoresponder_only;
        }
    }

    return \@processed_data;
}

1;

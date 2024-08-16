package Cpanel::Email::Aliases;

# cpanel - Cpanel/Email/Aliases.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie                      ();
use Cpanel::Context                      ();
use Cpanel::ConfigFiles                  ();
use Cpanel::Email::Config::Perms         ();
use Cpanel::Email::Utils                 ();
use Cpanel::LoadFile::ReadFast           ();
use Cpanel::SafeFile                     ();
use Cpanel::StringFunc::Trim             ();
use Cpanel::Validate::FilesystemNodeName ();

#STATIC METHOD
sub domain_has_entry {
    my ($domain) = @_;

    #sanity - FilesystemNodeName is safe, this was  Cpanel::Validate::Domain::valid_wild_domainname_or_die
    #and it was too slow
    Cpanel::Validate::FilesystemNodeName::validate_or_die($domain);

    return Cpanel::Autodie::exists("$Cpanel::ConfigFiles::VALIASES_DIR/$domain") ? 1 : 0;
}

#Parameters:
#   - domain (required)
#
sub new {
    my ( $class, %OPTS ) = @_;

    my $domain = $OPTS{'domain'} || die 'Need “domain”!';

    #sanity - FilesystemNodeName is safe, this was  Cpanel::Validate::Domain::valid_wild_domainname_or_die
    #and it was too slow
    Cpanel::Validate::FilesystemNodeName::validate_or_die($domain);

    my ( $finaldest, $dest, %defaddys_lookup );

    my $domain_file = "$Cpanel::ConfigFiles::VALIASES_DIR/$domain";

    my %aliases;

    my $self = {
        _aliases     => \%aliases,
        _domain      => $domain,
        _domain_file => $domain_file,
    };

    bless $self, $class;

    if ( -r $domain_file ) {
        local ( $!, $^E );

        # Users can open their own files, but they shouldn't have write perms on the dir so the .lock file will error
        my $vllock = Cpanel::SafeFile::safeopen_skip_dotlock_if_not_root( my $vfh, "<", $domain_file );    #safesecure2
        die "Failed to obtain lock on aliases file for $domain!" if !$vllock;

        my $data;
        Cpanel::LoadFile::ReadFast::read_all_fast( $vfh, $data );

        foreach ( split( m{\n}, $data ) ) {
            ( $dest, $finaldest ) = split( /:/, $_, 2 );

            next if !defined $finaldest;

            Cpanel::StringFunc::Trim::ws_trim( \$finaldest );

            foreach my $addy ( Cpanel::Email::Utils::get_forwarders_from_string($finaldest) ) {
                $addy = Cpanel::Email::Utils::normalize_forwarder_quoting($addy);
                if ( $dest eq '*' ) {
                    $defaddys_lookup{$addy} = undef;
                }
                else {
                    $aliases{$dest}{$addy} = 1;
                }
            }
        }

        $self->{'_default'} = join( ',', sort keys %defaddys_lookup );

        $self->_secure_domain_file($vfh);

        Cpanel::SafeFile::safeclose( $vfh, $vllock );
    }

    return $self;
}

sub save {
    my ($self) = @_;

    die "Do not run as root!" if !$>;

    # Users can open their own files, but they shouldn't have write perms on the dir so the .lock file will error
    my $vllock = Cpanel::SafeFile::safeopen_skip_dotlock_if_not_root( my $vfh, '>', $self->{'_domain_file'} );    #safesecure2
    if ( !$vllock ) {
        die "Error opening “$self->{'_domain_file'}” to write: $!";
    }

    my $aliases_hr = $self->{'_aliases'};
    my ( $line, $lcount, $destinations_hr );

  ADDR:
    foreach my $mail ( sort keys %$aliases_hr ) {
        $line            = '';
        $lcount          = 0;
        $destinations_hr = $aliases_hr->{$mail};

      FWD:
        foreach my $addy ( sort keys %$destinations_hr ) {

            # if we have one :fail: type entry then its the only one allowed since the
            # ones before it will be ignored and the ones after it will be part of the message
            if ( $addy =~ /^[\s"]*\:(fail|defer|blackhole|include)\:/ ) {
                $lcount++;
                $line = $addy;
                $line =~ s{^\"|\"$}{}g;
                last FWD;
            }

            next if $destinations_hr->{$addy} != 1;

            $lcount++;
            $addy = Cpanel::StringFunc::Trim::ws_trim($addy);
            $addy =~ s/[\f\r\n]*//g;

            # add quotes back if there is still space and we are not a :name: type entry
            if ( $addy !~ /^[\s"]*\:(fail|defer|blackhole|include)\:/ && $addy =~ m/\s/ && $addy !~ m/\A"/s ) {
                $addy = qq{"$addy"};
            }

            if ( $addy !~ m/mwrap / ) {    #get rid of the cp2 nightmare
                $line .= $addy . ",";
            }
        }
        $line =~ s/\,$//g;
        if ( $lcount > 0 ) {
            print $vfh "$mail: $line\n";
        }
    }

    if ( length $self->{'_default'} ) {
        print $vfh "*: $self->{'_default'}\n";
    }

    $self->_secure_domain_file($vfh);

    Cpanel::SafeFile::safeclose( $vfh, $vllock );

    return;
}

sub _secure_domain_file {
    my ( $self, $vfh ) = @_;

    Cpanel::Email::Config::Perms::secure_mail_db_file( $self->{'_domain'}, $vfh );

    return;
}

sub set_default_destination {
    my ( $self, $default ) = @_;

    $self->{'_default'} = $default;

    return;
}

sub get_default_destination {
    my ($self) = @_;

    return $self->{'_default'};
}

sub add {
    my ( $self, $alias, $dest ) = @_;

    $dest = Cpanel::Email::Utils::normalize_forwarder_quoting($dest);
    $self->{'_aliases'}{$alias}{$dest} = 1;

    return;
}

#This returns a boolean that indicates whether the destination
#*was* active.
sub remove {
    my ( $self, $alias, $dest ) = @_;

    my $ret = $self->{'_aliases'}{$alias};
    if ($ret) {
        $ret = delete $self->{'_aliases'}{$alias}{$dest};

        if ( !%{ $self->{'_aliases'}{$alias} } ) {
            delete $self->{'_aliases'}{$alias};
        }
    }

    return $ret ? 1 : 0;
}

sub remove_alias {
    my ( $self, $alias ) = @_;

    delete $self->{'_aliases'}{$alias};

    return;
}

sub get_aliases {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return keys %{ $self->{'_aliases'} };
}

sub get_destinations {
    my ( $self, $alias ) = @_;

    if ( !length $alias ) {
        warn 'Cannot perform lookup for empty alias';
        return;
    }

    Cpanel::Context::must_be_list();

    my $dests_hr = $self->{'_aliases'}{$alias};

    return keys %$dests_hr;
}

1;

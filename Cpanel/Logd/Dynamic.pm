package Cpanel::Logd::Dynamic;

# cpanel - Cpanel/Logd/Dynamic.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Logd::MiniDynamic    ();
use Cpanel::SafeDir::MK          ();
use Cpanel::SafeDir::Read        ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::Server::Type         ();
use Cpanel::Template             ();

*get_logd_link_entry_of_path = *Cpanel::Logd::MiniDynamic::get_logd_link_entry_of_path;
*get_path_of_logd_link_entry = *Cpanel::Logd::MiniDynamic::get_path_of_logd_link_entry;
*_fixup_entry_name           = *Cpanel::Logd::MiniDynamic::_fixup_entry_name;

# qr() kill perlcc:
# my $symlink_rgx = qr([.] $Cpanel::Logd::MiniDynamic::symlink_ext \z)xms;

sub get_logs_in_dir_lookup_hr {
    my ( $dir, $ignore ) = @_;
    return       if !-d $dir;
    $ignore = {} if ref $ignore ne 'HASH';

    my $logs = {};

    foreach my $file ( Cpanel::SafeDir::Read::read_dir($dir) ) {
        next if exists $ignore->{$file};
        next if -d "$dir/$file";
        next if $file !~ /log/i;
        next if $file =~ /\.gz$/i;
        $logs->{$file} = "$dir/$file";
    }

    # TODO maybe?: what about log rotation $entries whose targets do not exist? they should be in this list to so that non_existant will show up in menu ?

    return $logs;
}

# TODO maybe?: yaml config dir && corresponding *_logd_yaml_entry() funtions for more complex setups ?

sub logd_link_entry_exists {
    my ($ent) = @_;
    $ent = _fixup_entry_name($ent);
    return 1 if -l "$Cpanel::Logd::MiniDynamic::symlink_dir/$ent";
    return;
}

sub get_custom_logd_link_paths {
    return if !-d $Cpanel::Logd::MiniDynamic::symlink_dir;

    my @cust;
    my %seen;

    foreach my $cust ( Cpanel::SafeDir::Read::read_dir($Cpanel::Logd::MiniDynamic::symlink_dir) ) {
        next if substr( $cust, -1 - length $Cpanel::Logd::MiniDynamic::symlink_ext ) ne ".$Cpanel::Logd::MiniDynamic::symlink_ext";

        my $target = get_path_of_logd_link_entry($cust);
        next if !$target;

        if ( !exists $seen{$target} && -f $target ) {
            push @cust, $target;
            $seen{$target}++;
        }
    }
    return wantarray ? @cust : \@cust;
}

sub create_logd_link_entry {
    my ( $ent, $target, $force ) = @_;
    $ent = _fixup_entry_name($ent);
    Cpanel::SafeDir::MK::safemkdir($Cpanel::Logd::MiniDynamic::symlink_dir) if !-d $Cpanel::Logd::MiniDynamic::symlink_dir;
    my $desti = join( '/', $Cpanel::Logd::MiniDynamic::symlink_dir, $ent );

    # link already exists
    if ( -l $desti ) {
        if ($force) {
            unlink $desti;
        }
        else {

            # check target : return true if defined as expected, false in any other case
            my $current_target = readlink $desti;
            return $current_target && $current_target eq $target ? 1 : undef;
        }
    }
    symlink $target, $desti;
}

sub delete_logd_link_entry {
    my ($ent) = @_;
    $ent = _fixup_entry_name($ent);
    return 1 if !-l "$Cpanel::Logd::MiniDynamic::symlink_dir/$ent" && !-e "$Cpanel::Logd::MiniDynamic::symlink_dir/$ent";
    unlink "$Cpanel::Logd::MiniDynamic::symlink_dir/$ent";
}

sub update_logd_link_entry {
    my ( $ent, $new_target ) = @_;
    $ent = _fixup_entry_name($ent);

    if ( delete_logd_link_entry($ent) ) {
        return create_logd_link_entry( $ent, $new_target );
    }
    return;
}

sub whm_cgi_app {
    my ($app_config_hr) = @_;
    $app_config_hr->{'prefix'} ||= '';
    $app_config_hr->{'prefix'} .= '_' if $app_config_hr->{'prefix'};

    require Whostmgr::HTMLInterface;
    require Whostmgr::ACLS;
    Whostmgr::ACLS::init_acls();
    if ( !Whostmgr::ACLS::hasroot() ) {
        print "Content-type: text/plain\n\n";
        print "Access Denied";
        return;
    }

    require Cpanel::Form::Param;
    require Cpanel::Encoder::Tiny;

    my $prm    = Cpanel::Form::Param->new();
    my $action = $prm->param('action') || '';

    # TODO maybe?: have an 'always' key for files that may not exist ?
    my $cpanel_logs_hr = get_logs_in_dir_lookup_hr( $app_config_hr->{'path'}, $app_config_hr->{'ignore'} );
    my $image;
    if ( $app_config_hr->{'name'} =~ m{apache}i ) {
        $image = '/images/logrotation.gif';
    }

    print "Content-type: text/html\n\n";
    Whostmgr::HTMLInterface::defheader( undef, undef, undef, undef, undef, undef, undef, undef, 'cpanel_log_rotation_configuration' );

    print <<'END_CSS';
        <style type="text/css">
          .info_box {
            background-color:#FFFFCC;
            border:1px solid #666666;
            margin-left:20px;
            padding:5px;
            width:500px;
         }
       </style>
END_CSS

    print qq{<div style="margin-left: 20px;">\n};

    if ( $action eq 'save' ) {
        my %files_to_rotate;
        @files_to_rotate{ $prm->param('cpanel_log') } = ();
        for my $base ( sort keys %{$cpanel_logs_hr} ) {
            $base = Cpanel::Encoder::Tiny::safe_html_encode_str($base);    # just in case
            next if !exists $cpanel_logs_hr->{$base};                      # encoder changed it, probably means bad file name
            if ( exists $files_to_rotate{$base} ) {

                if ( Cpanel::Logd::Dynamic::update_logd_link_entry( 'cp_' . $app_config_hr->{'prefix'} . $base, $cpanel_logs_hr->{$base} ) ) {
                    print "<p>'$base' is in rotation</p>\n";
                }
                else {
                    print qq{<p class="error">Could not ensure that '$base' is in rotation</p>\n};
                }
            }
            else {
                if ( Cpanel::Logd::Dynamic::delete_logd_link_entry( 'cp_' . $app_config_hr->{'prefix'} . $base ) ) {
                    print "<p>'$base' is not in rotation</p>\n";
                }
                else {
                    print qq{<p class="error">Could not verify that '$base' is not in rotation</p>n};
                }
            }
        }

        my ($file_name) = reverse( split( /\//, $ENV{'SCRIPT_NAME'} ) );
        Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::Logd::MiniDynamic::symlink_dir/lastsaved.$file_name");
        print qq{<p>[<a href="$ENV{'SCRIPT_URI'}">Back</a>]</p>\n};
    }
    else {

        Cpanel::Template::process_template(
            'whostmgr',
            {
                'template_file' => 'cpanel_log_rotation_form_header.tmpl',
                'logs'          => $cpanel_logs_hr,
                'app_path'      => $app_config_hr->{'path'},
                'dnsonly'       => Cpanel::Server::Type::is_dnsonly() ? 1 : 0,
            },
        );

        my $in_rotation = qq{<span class="status">(in rotation)</span>};

        for my $base ( sort keys %{$cpanel_logs_hr} ) {
            $base = Cpanel::Encoder::Tiny::safe_html_encode_str($base);    # just in case
            next if !exists $cpanel_logs_hr->{$base};                      # encoder changed it, probably means bad file name

            if ( Cpanel::Logd::Dynamic::logd_link_entry_exists( 'cp_' . $app_config_hr->{'prefix'} . $base ) ) {
                print qq{      <input type="checkbox" name="cpanel_log" value="$base" checked="checked" /> $base $in_rotation<br />\n};
            }
            else {
                print qq{      <input type="checkbox" name="cpanel_log" value="$base" /> $base<br />\n};
            }
        }
        print qq{      <input type="submit" value="Save" class="btn-primary" />\n    </form>\n};
    }

    print "</div>\n";
    return Whostmgr::HTMLInterface::deffooter();
}

1;

__END__

=head1 Functions

All functions return data/true on success. False other wise.

The '$entry' in the examples below are all letters, numbers, and underscore identifiers of the entry.

Probably the most used will update_logd_link_entry() and delete_logd_link_entry()

=head2 get_custom_logd_link_paths()

Returns a list of paths that get rotated. Scalar context returns array ref.

=head2 get_path_of_logd_link_entry( $entry )

Returns the path to rotate of a given entry.

=head2 create_logd_link_entry( $entry, $absolute_path_of_file_to_rotate )

Creates an entry to rotate a file.

=head2 delete_logd_link_entry( $entry );  update_logd_link_entry( $entry, $absolute_path_of_new_file_to_rotate )

Updates the $entry's path to rotate. Wil be created if it does not exist.

=head2 get_logd_link_entry_of_path($path)

Return the $entry that points to $path. If it does not exist this will simply return; false.

=head1 Caveats

=head2 $entry names starting with 'cp_' are reserved for internal use.

Using them in custom code may/will get them overwritten or removed.

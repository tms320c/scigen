#!/usr/bin/perl -w

#    This file is part of SCIgen.
#
#    SCIgen is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    SCIgen is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with SCIgen; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


use strict;
use scigen;
use IO::File;
use Getopt::Long;
use IO::Socket;

my $tmp_dir = "/tmp/scitmp.$$";
my $tmp_pre = "$tmp_dir/scimakehtml.";
my $html_file = "$tmp_pre$$.html";
my $bib_file = "$tmp_dir/scigenbibfile.html";
my $css_files = "IEEEtran.cls IEEE.bst";
my @authors;
my $seed;
my $remote = 0;
my $title;

sub usage {
    select(STDERR);
    print <<EOUsage;
    
$0 [options]
  Options:

    --help                    Display this help message
    --author <quoted_name>    An author of the paper (can be specified 
                              multiple times)
    --seed <seed>             Seed the prng with this
    --savedir <dir>           Save the files in a directory
    --remote                  Use a daemon to resolve symbols
    --talk                    Make a talk, instead of a paper
    --title <title>           Set the title (useful for talks)
    --sysname <name>          Set the system name

EOUsage

    exit(1);

}

# Get the user-defined parameters.
# First parse options
my %options;
&GetOptions( \%options, "help|?", "author=s@", "seed=s", 
	     "savedir=s", "remote", "talk", "title=s", "sysname=s" )
    or &usage;

if( $options{"help"} ) {
    &usage();
}

if( !defined $options{"savedir"} ) {
    &usage();
}

if( defined $options{"author"} ) {
    @authors = @{$options{"author"}};
}
if( defined $options{"remote"} ) {
    $remote = 1;
}
if( defined $options{"title"} ) {
    $title = $options{"title"};
}
if( defined $options{"seed"} ) {
    $seed = $options{"seed"};
} else {
    $seed = int rand 0xffffffff;
}
srand($seed);

my $name_dat = {};
my $name_RE = undef;
my $html_dat = {};
my $html_RE = undef;

if( !-d $tmp_dir ) {
    system( "mkdir -p $tmp_dir" ) and die( "Couldn't make $tmp_dir" );
}

my $sysname;
if( defined $options{"sysname"} ) {
    $sysname = $options{"sysname"};
} else {
    $sysname = &get_system_name();
}

my $html_fh; 
my $start_rule;
if( defined $options{"talk"} ) {
    $html_fh = new IO::File ("<talkrules-h.in");
    $start_rule = "SCITALK_HTML";
} else {
    $html_fh = new IO::File ("<scirules-h.in");
    $start_rule = "SCIPAPER_HTML";
}

my @a = ($sysname);
$html_dat->{"SYSNAME"} = \@a;
# add in authors
$html_dat->{"AUTHOR_NAME"} = \@authors;
my $s = "";
for( my $i = 0; $i <= $#authors; $i++ ) {
    $s .= "AUTHOR_NAME";
    if( $i < $#authors-1 ) {
	$s .= ", ";
    } elsif( $i == $#authors-1 ) {
	$s .= " and ";
    }
}
my @b = ($s);
$html_dat->{"SCIAUTHORS"} = \@b;

scigen::read_rules ($html_fh, $html_dat, \$html_RE, 0);
if( defined $title ) {
    my @a = ($title);
    $html_dat->{"SCI_TITLE"} = \@a;
}
my $html_text = scigen::generate ($html_dat, $start_rule, $html_RE, 0, 1);
open( MAIN_HTML, ">$html_file" ) or die( "Couldn't open $html_file for writing" );
print MAIN_HTML $html_text;
close( MAIN_HTML );

# for every figure you find in the file, generate a figure
open( MAIN_HTML, "<$html_file" ) or die( "Couldn't read $html_file" );
my %citelabels = ();
my @figures = ();
while( <MAIN_HTML> ) {

    my $line = $_;

#    if( /figure=(figure.*),/ ) {
    if( /<[iI]mg\b(?=\s)(?=(?:[^>=]|='[^']*'|="[^"]*"|=[^'"][^\s>]*)*?\ssrc=['"]([^"]*)['"])(?:[^>=]|='[^']*'|="[^"]*"|=[^'"\s]*)*\s?>/ ) {
	my $figfile = "$tmp_dir/$1";
	my $done = 0;
	while( !$done ) {
	    my $newseed = int rand 0xffffffff;
	    my $color = "";
	    if( defined $options{"talk"} ) {
		$color = "--color"
	    }
	    system( "./make-graph-html.pl --file $figfile --seed $newseed $color" ) 
		or $done=1;
	}
	push @figures, $figfile;
    }

    if( /[=\{](dia[^\,\}]*)[\,\}]/ ) {
	my $figfile = "$tmp_dir/$1";
	my $done = 0;
	while( !$done ) {
	    my $newseed = int rand 0xffffffff;
	    if( `which neato` ) {
		(system( "./make-diagram-html.pl --sys \"$sysname\" " . 
			 "--file $figfile --seed $newseed" ) or 
		 !(-f $figfile)) 
		    or $done=1;
	    } else {
		system( "./make-graph-html.pl --file $figfile --seed $newseed" ) 
		    or $done=1;
	    }
	}
	push @figures, $figfile;
    }

    if( /[=\{]([^\{]*)-(talkfig[^\,\}]*)[\,\}]/) {
	my $figfile = "$tmp_dir/$1-$2";
	my $type = $1;
	my $done = 0;
	while( !$done ) {
	    my $newseed = int rand 0xffffffff;
	    system( "./make-talk-figure-html.pl --file $figfile --seed $newseed --type $type" ) 
		or $done=1;
	}
	push @figures, $figfile;
    }

    # find citations
    while( $line =~ s/(cite\:\d+)[,\}]// ) {
        my $citelabel = $1;
	$citelabels{$citelabel} = 1;
    }
    if( $line =~ /(cite\:\d+)$/ ) {
        my $citelabel = $1;
	$citelabels{$citelabel} = 1;
    }

}
close( MAIN_HTML );

# generate bibtex 
foreach my $author (@authors) {
    for( my $i = 0; $i < 10; $i++ ) {
	push @{$html_dat->{"SCI_SOURCE"}}, $author;
    }
}
open( BIB, ">$bib_file" ) or die( "Couldn't open $bib_file for writing" );
foreach my $clabel (keys(%citelabels)) {
    my $sysname_cite = &get_system_name();
    @a = ($sysname_cite);
    $html_dat->{"SYSNAME"} = \@a;
    my @b = ($clabel);
    $html_dat->{"CITE_LABEL_GIVEN"} = \@b;
    scigen::compute_re( $html_dat, \$html_RE );
    my $bib = scigen::generate ($html_dat, "BIBTEX_ENTRY", $html_RE, 0, 1);
    print BIB $bib;
    
}
close( BIB );

my $seedstring = "seed=$seed ";
foreach my $author (@authors) {
    $seedstring .= "author=$author ";
}

my $f = $options{"tar"};
my $tartmp = "$tmp_dir/tartmp.$$";
my $all_files = "$html_file $css_files @figures $bib_file";
system( "mkdir $tartmp; cp $all_files $tartmp/;" ) and die( "Couldn't mkdir $tartmp" );
$all_files =~ s/$tmp_dir\///g;
system( "echo $seedstring > $tartmp/seed.txt" ) and die( "Couldn't cat to $tartmp/seed.txt" );
$all_files .= " seed.txt";

# saving everything
my $dir = $options{"savedir"};
# WARNING: we delete this directory if it exists
if( -d $dir ) {
	system( "rm -rf $dir" ) and die( "Couldn't rm existing $dir" );
}
system( "mv $tartmp $dir" ) and die( "Couldn't move $tartmp to $dir" );

system( "rm $tmp_pre*" ) and die( "Couldn't rm" );
unlink( @figures );
unlink( "$bib_file" );
system( "rm -f $tmp_dir/dia*.tmp; rmdir $tmp_dir" );

sub get_system_name {

    if( $remote ) {
	return &get_system_name_remote();
    }

    if( !defined $name_RE ) {
	my $fh = new IO::File ("<system_names.in");
        scigen::read_rules ($fh, $name_dat, \$name_RE, 0);
    }

    my $name = scigen::generate ($name_dat, "SYSTEM_NAME", $name_RE, 0, 0);
    chomp($name);

    # how about some effects?
    my $rand = rand;
    if( $rand < .1 ) {
	$name = "<em>$name</em>";
    } elsif( length($name) <= 6 and $rand < .4 ) {
	$name = uc($name);
    }

    return $name;
}

sub get_system_name_remote {

    my $sock = IO::Socket::INET->new( PeerAddr => "localhost", 
				      PeerPort => $scigen::SCIGEND_PORT,
				      Proto => 'tcp' );
    
    my $name;
    if( defined $sock ) {
	$sock->autoflush;
	$sock->print( "SYSTEM_NAME\n" );
	
	while( <$sock> ) { 
	    $name = $_;
	}
	$sock->close();
	undef $sock;
	
    } else {
	print STDERR "socket didn't work\n";
    }

    chomp($name);
    return $name;
}

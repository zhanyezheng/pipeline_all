#!/usr/bin/perl -w


#Elzo de Wit
#Netherlands Cancer Institute
#e.d.wit@nki.nl

#Select sequences from the genome from a given
#fragment map and determine whether they are unique
#in the genome. If they are not unique store the
#position in the repeat map.

#You will need to create a new repeat map for every
#fragment map (i.e. restriction enzyme combination) and
#sequence length used in the 4C.

#Please provide an existing directory (e.g. repeats/). In
#this directory a new directory is created based on the
#sequence length option that is provided.

#The options:
#frag_map: the fragment map generated by generate_fragment_map.pl
#re: restriction site of the 1st restriction enzyme
#seq_len: the length of the sequence (without the read primer sequence)
#         this means if you have sequence of 65, with a primer sequence of 20
#         and a GATC as a restriction site (4), the sequence length should be
#         65 - 20 + 4 = 49
#reference: reference genome, should be the same as on which the fragment map is based
#out_dir: directory in which the repeat map directory should be created (e.g if directory
#         is repeats/ and seq_len is 49 a directory repeats/49/ will be created
#threads: optional parameter, for the amount of threads used in bwa

use strict;

my $frag_map  = shift @ARGV or usage();
my $re        = shift @ARGV or usage();
my $seq_len   = shift @ARGV or usage();
my $reference = shift @ARGV or usage();
my $out_dir   = shift @ARGV or usage();
my $threads   = shift @ARGV;


#create output directory with the correct sequence length
$out_dir .= "/" . $seq_len;
mkdir $out_dir;

my @files = glob "$frag_map/*txt";


#create a temporary bed file
`cat /dev/null > temp_frag.bed`;

print "Creating BED file from fragments\n";
#create a bed file
for my $file ( @files ){
	createBed( $file, $seq_len );   ##$seq_len 为 去掉引物后的序列长度
}	

$threads = 1 if not defined $threads;


print "Selecting sequences from the genome\n";
#select the sequences using fastaFromBed
system("fastaFromBed -fi $reference -bed temp_frag.bed -fo temp_frag_seq.fa");  ## 根据位置信息得到fasta 文件，根据位置在fasta中提取相应的序列##chr1:15171-15273
                                                                                                                                          ## GATCCCTGACCCAGCACCGGGCACTGATGAGACAGCGGCTGTTTGAGGAGCCACCTCCCAGCCACCTCGGGGCCAGGGCCAGGGTGTGCAGCAccactgtac																																		
print "Mapping sequences to the genome\n";
my $mapping_command = "bwa bwasw -t $threads $reference temp_frag_seq.fa > temp_frag_seq.sam"; ## fasta文件得到Sam文件
system($mapping_command);

print "Parsing resulting SAM file\n";
my %files;
open SAM, "temp_frag_seq.sam" or die "Cannot open file: $!";
while(<SAM>){
	chomp;
	next if /^@/;  ## next是退出某一次循环， if 后面是条件 ，当开头是@ 时，退出这个循环，即不读开头是@的行；
	my ($id, $qual, $seq ) = (split /\t/)[0,4,9];
	next if $qual > 0; ##跳过 $qual > 0 的行；   ## $qual 为 MAPQ 比对质量这列，MAPQ 值越高，序列特异性越好，唯一比对到基因组上，因为这里是要选重复比对到基因组上的序列，所以需要选MAPQ = 0 的列，跳过MAPQ >0 的列；
	$id =~ s/^>//;
	my ($chrom, $start, $end) = split /[-:]/,$id;
	my $pos;
	$seq = uc($seq);    ##序列转化成大写
	if($seq =~ /^$re/){
		$pos = $start+1;  ## 如果开头是酶切位点，记录start 的信息
	}else{
		$pos = $end;  ## 反之，如果结尾是酶切位点，记录end 的信息  ，即这步是记录酶切位点的位置
	}
	if(not defined $files{$chrom}){
		my $fh;
		open $fh, ">$out_dir/$chrom\.txt" or die "Cannot create file: $!";
		$files{$chrom} = $fh;
	}
	my $out_fh = $files{$chrom};
	print $out_fh $pos, "\n";
}

#remove the temporary files since we got to this point
system("rm temp_frag.bed temp_frag_seq.fa temp_frag_seq.sam");


#generate tje reverse complement
sub revComp{
	my $seq = shift;
	$seq =~ tr/ACGT/TGCA/;
	reverse $seq;
}	

sub createBed{
	my ($file, $len) = @_;
	open FRAG, $file or die "Cannot open file: $!";
	open OUT, ">>temp_frag.bed" or die "Cannot open stream: $!";
	my ($chrom) = $file =~ /.*\/(chr.*).txt/;
	while(<FRAG>){
		chomp;
		my ($start,$end,$ori) = split /\t/;
		$start--;
		if( $end - $start > $len ){   ### $len 为去掉引物后的序列长度
			if($ori == 5){
				print OUT join("\t", ($chrom, $start, $start+$len-1)), "\n";  ##若为5' 则位置为 star 到 star+序列长度 -1
			}else{
				print OUT join("\t", ($chrom, $end-$len+1, $end)), "\n";   ##若为3' 则位置为 end-序列长度+1 到 end
			}
		}else{
			print OUT join("\t", ($chrom, $start, $end)), "\n";
		}
	}
	close OUT;
}	


sub usage{
	print "getRepeats.pl fragment_map_dir restriction_site sequence_length reference output_directory [threads]\n";
	exit;
}	

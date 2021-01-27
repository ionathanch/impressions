# *Impressions*

Nitin Agrawal
<br/>
nitina@cs.wisc.edu

## Quickstart

Run `make` to install, then run `./impress <inputfile>`. The default input file is `./inputfile`.

Additional software is required in `extension_helpers` for certain file extensions:
* id3v2 for mp3
* gif for gif/jpeg files

## Input file format

### Parameters

* `Parent_Path: ./impress_home/ 1`
  <br/>
  Specifies where to create the test file system.
  1/0 toggles whether this will be used or not.
* `Actuallogfile: /root/impress/Desksearch/Results/Logs 0`
  <br/>
  Specifies where log files will be maintained.
  1/0 toggles whether this will be used or not.
* `Randseeds: Direct 10 10 20 30 40 50 60 70 80 90 100`
  <br/>
  Specify seeds for random number generators to ensure reproducibility.
  If more randseeds are needed, change the number right after `Direct`
  which specifies the number of random seeds.
* `FScapacity: 100 GB`
  <br/>
  Total capacity of the disk; does not affect anything.
* `FSused: 45 GB`
  <br/>
  Size of the desired file system. The actual created file system
  can be a little off from the desired value.
* `Numfiles: NO K`
  <br/>
  Number of files desired. First arg is number, second arg is unit:
  `N` for 10^0, `K` for 10^3, `M` for 10^6, `B` for 10^9.
  If first arg is `NO`, Impressions will calculate based on `FSused`.
* `Numdirs: NO K`
  <br/>
  Number of directories desired. First arg is number, second arg is unit:
  `N` for 10^0, `K` for 10^3, `M` for 10^6, `B` for 10^9.
  If first arg is `NO`, Impressions will calculate based on `FSused`.
* `Filesperdir: 10.2 N`
  <br/>
  Mean number of files in a directory.
* `FilesizeDistr: Direct 3 99994 29 0.91`
  <br/>
  File size distribution. 3 is number of params.
  First arg is bias for lognormal out of 100000;
  second arg is exponent for Pareto base (Xm);
  third arg is Pareto shape (alpha).
* `FilecountDistr: Direct 2 9.48 2.45663283`
  <br/>
  File count/size lognormal distribution.
  First arg is mu; second arg is sigma.
* `Dircountfiles: Direct 2 2 2.36`
  <br/>
  Directory sizes inverse polynomial distribution.
  First arg is degree, second arg is offset.
* `DirsizesubdirDistr: Indir DirsizesubdirDistr.txt`
* `Fileswithdepth: Direct 10`
  <br/>
  File depth Poisson distribution. Arg is lambda (mean).
* `Layoutscore: 1.0`
  <br/>
  Desired layout score. 1.0 is perfectly laid out.
* `Actualfilecreation: 1`
  <br/>
  If this is 0 then no files or dirs will be created.
  If this is 1 then files and dirs will be created.
  If this is 2 then only dirs will be created.

### Special flags

* `SpecialFlags: 10`: Number of flags there are.
* `Flat 0`: If 1, create a flat tree.
* `Deep 0`: If 1, create a deep tree.
* `Ext -1`: If -1, Impressions select extensions; otherwise, the provided number selects from the list of extensions in `extension.cpp`.
* `Wordfreq 0`: The type of content inside files.
* `Large2Small 0`: Not currently used.
* `Small2Large 0`: Not currently used.
* `Depthwithcare 1`: If 1, place files carefully according to depth distributions.
* `Filedepthpoisson 1`: If 1, use the Poisson distribution choice for file depth.
* `Dircountfiles 1`: If 1, use inverse polynomial distribution choice for number of files in directory.
* `Constraint 0`: If 1, activate constraint solving for `FSused` and `Numfiles`.

### Printing flags

`Printwhat` is the number of printing flags there are; use 0/1 to toggle off/on.

```
Printwhat: 10
ext 0
sizebin 0
size 0
initial 0
final 0
depth 0
tree 0
subdirs 0
dircountfiles 0
constraint 0
SpecialDirBias
```

## Significant code changes

In the `montecarlo` function in `montecarlo.cpp` appears this nested loop:

```cpp
list<dir> LD;
list<dir>::iterator ni;
...
int montecarlo(int numdirs) {
    ...
    LD.push_front(Dirs[0]);
    ...
    for (long i = 1; i < numdirs; i++) {
        long token_uptil_now = 0, sum_childs_plus2 = 2;
        long token = (rand() % sum_childs_plus2) + 1;
        ni = LD.begin();
        token_uptil_now += (*ni).subdirs+2;
        while (token_uptil_now < token) {
            ni++;
            token_uptil_now+= (*ni).subdirs+2;
        }
        ...
        LD.push_back(Dirs[i]);
        sum_childs_plus2+=2+1;
        ...
    }
    ...
}
```

This is very slow when `numdirs` is large, mostly due to the `while` loop that walks the iterator. For now, I replace this with a direct access into the middle of the iterator. This requires an iterator capable of random access, but at the same time the container being iterated still needs the capability to have elements pushed onto its front and back, so I replace the list with a dequeue. There is probably a more proper fix to this, but likely requires actually understanding the Monte Carlo simulation code.

```cpp
deque<dir> LD;
deque<dir>::iterator ni;
...
int montecarlo(int numdirs) {
    ...
    for (long i = i; i < numdirs; i++) {
        ...
        ni = LD.begin();
        ni += token / 3;
        ...
    }
    ...
}
```

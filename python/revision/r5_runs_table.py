"""
R5 (revision, reviewer 2 comment M3): collect test AUC of the published run, the
same-seed refit and the seed refits (101, 202, 303 and, for the neural families,
404) and tabulate the EO contrasts over runs.

Usage: python r5_runs_table.py <factorial7_out directory>
Reads factorial7_results_BEFORE.csv (the published run, saved before the refit),
factorial7_results.csv (refit at seed 20260910) and repeat_seed*/factorial7_results.csv.
Only saved result files are read. Nothing is fitted, tuned or selected.
"""
import sys, os
import pandas as pd, numpy as np
U=os.path.join(sys.argv[1] if len(sys.argv)>1 else 'factorial7_out','')
runs={'published':U+'factorial7_results_BEFORE.csv','refit1':U+'factorial7_results.csv'}
for s in [101,202,303,404]: runs[f's{s}']=U+f'repeat_seed{s}/factorial7_results.csv'
rows=[]
for k,f in runs.items():
    d=pd.read_csv(f).dropna(subset=['auc_test']).drop_duplicates(['family','arm'],keep='last')
    d['run']=k; rows.append(d[['run','family','arm','auc_test','auc_dev','recall_a20']])
A=pd.concat(rows)
A.to_csv('r5_all_runs_long.csv',index=False)
W=A.pivot_table(index=['family','arm'],columns='run',values='auc_test')
cons=[('F+SP','F+SP+EO'),('F','F+EO'),('SPA','EO+SPA')]
out=[]
for f in ['LR','RF','XGB','MLP','STCRAAN']:
    for a0,a1 in cons:
        if (f,a0) in W.index and (f,a1) in W.index:
            d=(W.loc[(f,a1)]-W.loc[(f,a0)]).dropna()
            out.append(dict(family=f,contrast=f'{a0}->{a1}',n=len(d),mean=d.mean(),sd=d.std(ddof=1) if len(d)>1 else np.nan,min=d.min(),max=d.max(),n_neg=(d<0).sum(),**{r:d.get(r,np.nan) for r in runs}))
O=pd.DataFrame(out); pd.set_option('display.width',250); pd.set_option('display.float_format',lambda v:f'{v:.5f}')
print(O.to_string(index=False)); O.to_csv('r5_contrast_by_run.csv',index=False)
# best-without-EO vs best-with-EO per run
for r in runs:
    s=A[A.run==r]
    if len(s)<10: continue
    noeo=s[~s.arm.str.contains('EO')].auc_test.max(); eo=s[s.arm.str.contains('EO')].auc_test.max()
    print(r,'best no-EO',round(noeo,5),s.loc[s[~s.arm.str.contains('EO')].auc_test.idxmax(),['family','arm']].tolist() if False else '', 'best EO',round(eo,5))
# family mean AUC over runs for FIN arms
M=A[A.arm.isin(['F','F+EO','F+SP','F+SP+EO','SPA','EO+SPA'])].groupby(['family','arm']).auc_test.agg(['count','mean','std','min','max'])
print(M.to_string())
M.to_csv('r5_auc_by_cell_over_runs.csv')

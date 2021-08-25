import os

DC: str = os.getenv('CI_DATA_CENTER')

if DC == 'asia':
    with open('asia.yaml', 'r+') as conf:
        with open('config', 'w') as export_file:
            export_file.write(conf.read())
    print('[OK] Selected cluster (Bangalore) = production.aibi-platform-bh.bh-dc-os-gsn-103.k8s.dyn.nesc.nokia.net')
elif DC == 'americas':
    with open('americas.yaml', 'r+') as conf:
        with open('config', 'w') as export_file:
            export_file.write(conf.read())
    print('[OK] Selected cluster (Franklin Park) = production.aibi-prod-fp.ch-dc-os-gsn-107.k8s.dyn.nesc.nokia.net')
elif DC == 'europe':
    with open('europe.yaml', 'r+') as conf:
        with open('config', 'w') as export_file:
            export_file.write(conf.read())
    print('[OK] Selected cluster (ESPOO) = production.aibi-platform-es.he-pi-os-gsn-101.k8s.dyn.nesc.nokia.net')
else:
    raise ValueError(f'Unknown CI_DATA_CENTER={DC}')

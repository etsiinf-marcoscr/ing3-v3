Pasos:
0) Crear una instancia EC2 (se usará de bastión de despliegue), tener a mano la IP pública
1) ```sudo yum install git -y```
2) ```git clone https://github.com/etsiinf-marcoscr/ing3-v3.git```
3) ```mkdir ing3-v3/ssh-key```
4) ```mkdir ~/.aws```
5) ```nano ~/.aws/credentials``` (pegar credenciales de AWS Details)
6) ```nano ~/.aws/config``` ([default] region=us-east-1) ··· Más detalles en https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-files.html
7) ```scp -i labsuser.pem labsuser.pem ec2-user@<IP_Publica_Bastion>:~/ing3-v3/ssh-key``` (subir la clave)
8) ```cd ing3-v3```
9) ```chmod +x deploy.sh```
10) ```./deploy.sh```
11) ```make deploy```

Al acabar:   
12) ```make delete```    
13) Borrar la EC2 de bastión   
